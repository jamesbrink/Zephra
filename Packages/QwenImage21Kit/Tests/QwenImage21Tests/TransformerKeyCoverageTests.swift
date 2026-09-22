import Foundation
import Testing
import ZephraQuantization
import ZephraTestSupport

@testable import QwenImage21

/// Every tensor the published transformer ships, accounted for before a weight is read.
///
/// This is the cheap way to be certain the module tree matches what it will be handed: the
/// expected names and shapes are derived from `transformer/config.json`, and the shard index and
/// headers say what is actually there. A name on one side and not the other is a rename, a
/// miscounted block, or something this port has forgotten — each of which is hours of parity
/// debugging when it is found later.
///
/// Nothing here loads a weight. The index and the headers only, so fourteen gigabytes are
/// checked in well under a second.
@Suite("Every published transformer tensor is accounted for")
struct TransformerKeyCoverageTests {
    @Test(
        "the transformer's 297 tensors are exactly the ones this architecture implies",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func transformerTensors() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let directory = snapshot.appending(path: "transformer")
        let configuration = try Self.configuration(in: directory)
        let published = try Self.publishedShapes(in: directory)
        let expected = Self.expectedTensors(configuration)

        #expect(published.count == 297)
        let absent = Set(expected.keys).subtracting(published.keys).sorted()
        let unaccounted = Set(published.keys).subtracting(expected.keys).sorted()
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent)"))
        #expect(
            unaccounted.isEmpty, Comment(rawValue: "present but unaccounted for: \(unaccounted)"))

        let wrong = expected.compactMap { name, shape -> String? in
            guard let actual = published[name], actual != shape else { return nil }
            return "\(name) is \(actual), expected \(shape)"
        }
        #expect(wrong.isEmpty, Comment(rawValue: wrong.sorted().joined(separator: "; ")))

        // There are no biases anywhere, which is what lets every linear be built the same way.
        #expect(!published.keys.contains { $0.hasSuffix(".bias") })
        // The layer norms are parameterless, so they appear in no shard at all.
        #expect(!published.keys.contains { $0.contains("img_norm") })
        #expect(published["norm_out.linear.weight"] == [configuration.innerDim, configuration.innerDim])
    }

    /// The reference's own names, which is what `sanitized` maps out of.
    static func expectedTensors(_ configuration: QwenImage21TransformerConfiguration)
        -> [String: [Int]]
    {
        let dim = configuration.innerDim
        let head = configuration.attentionHeadDim
        let mlp = configuration.mlpHiddenSize
        var tensors: [String: [Int]] = [
            "img_in.weight": [dim, configuration.inChannels * configuration.patchSize * configuration.patchSize],
            "txt_in.text_norm.weight": [configuration.contextInDim],
            "txt_in.in_layer.weight": [dim, configuration.contextInDim],
            "txt_in.out_layer.weight": [dim, dim],
            "time_text_embed.timestep_embedder.linear_1.weight": [
                dim, QwenImage21TimestepEmbedding.projectionChannels,
            ],
            "time_text_embed.timestep_embedder.linear_2.weight": [dim, dim],
            // One shared table for all 32 blocks, four vectors wide.
            "modulation.1.weight": [4 * dim, dim],
            "norm_out.linear.weight": [dim, dim],
            "proj_out.weight": [
                configuration.patchSize * configuration.patchSize * configuration.outChannels, dim,
            ],
        ]
        for layer in 0..<configuration.numLayers {
            let prefix = "transformer_blocks.\(layer)."
            for projection in ["to_q", "to_k", "to_v"] {
                tensors[prefix + "attn.\(projection).weight"] = [dim, dim]
            }
            tensors[prefix + "attn.to_out.0.weight"] = [dim, dim]
            tensors[prefix + "attn.norm_q.weight"] = [head]
            tensors[prefix + "attn.norm_k.weight"] = [head]
            tensors[prefix + "img_mlp.proj.weight"] = [mlp, dim]
            tensors[prefix + "img_mlp.gate_layer.weight"] = [mlp, dim]
            tensors[prefix + "img_mlp.out.weight"] = [dim, mlp]
        }
        return tensors
    }

    static func configuration(in directory: URL) throws -> QwenImage21TransformerConfiguration {
        try JSONDecoder()
            .decode(
                QwenImage21TransformerConfiguration.self,
                from: Data(contentsOf: directory.appending(path: "config.json"))
            )
            .validated()
    }

    /// Every tensor in the sharded component, by name, with its shape and none of its bytes.
    static func publishedShapes(in directory: URL) throws -> [String: [Int]] {
        struct Index: Decodable { let weightMap: [String: String] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let index = try decoder.decode(
            Index.self,
            from: Data(
                contentsOf: directory.appending(
                    path: "diffusion_pytorch_model.safetensors.index.json")))

        var shapes: [String: [Int]] = [:]
        for shard in Set(index.weightMap.values).sorted() {
            let header = try SafeTensorsHeader(contentsOf: directory.appending(path: shard))
            for entry in header.entries { shapes[entry.name] = entry.shape }
        }
        return shapes
    }
}
