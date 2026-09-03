import Foundation
import Testing

@testable import QwenImage

/// Every tensor the published snapshot ships, accounted for before a single module is written.
///
/// This is a cheap way to be certain the module tree about to be built matches the weights: the
/// expected names below are derived from the configuration, and the shard index says what is
/// actually there. A key on one side and not the other is a rename, a miscounted block, or a
/// component this port has forgotten. It is kept alongside the parity suites, which build the
/// modules, because it runs against the index alone and so needs no weights at all.
@Suite("Weight key coverage")
struct WeightKeyCoverageTests {
    @Test("the MMDiT's 1933 tensors are exactly the ones this architecture implies", .enabled(if: SnapshotUnderTest.isPresent))
    func transformerKeys() throws {
        let snapshot = try #require(SnapshotUnderTest.directory)
        let configuration = try QwenImageConfiguration(readingFrom: snapshot)
        let published = try Self.indexedKeys(
            snapshot.appending(
                path: "transformer/diffusion_pytorch_model.safetensors.index.json"))
        let expected = Self.expectedTransformerKeys(configuration.transformer)

        #expect(published.count == 1933)
        #expect(
            expected.subtracting(published).isEmpty,
            "expected but absent: \(expected.subtracting(published).sorted().prefix(5))")
        #expect(
            published.subtracting(expected).isEmpty,
            "present but unaccounted for: \(published.subtracting(expected).sorted().prefix(5))")
    }

    @Test("the text encoder's language half is loaded and its vision tower is not", .enabled(if: SnapshotUnderTest.isPresent))
    func textEncoderKeys() throws {
        let snapshot = try #require(SnapshotUnderTest.directory)
        let configuration = try QwenImageConfiguration(readingFrom: snapshot)
        let published = try Self.indexedKeys(
            snapshot.appending(path: "text_encoder/model.safetensors.index.json"))
        let expected = Self.expectedTextEncoderKeys(configuration.textEncoder)

        #expect(published.count == 729)
        #expect(
            expected.subtracting(published).isEmpty,
            "expected but absent: \(expected.subtracting(published).sorted().prefix(5))")

        // What is left over must be exactly the two things text-to-image never reads: the vision
        // tower, because no pixels are ever supplied, and the language-modelling head, because
        // Qwen-Image conditions on hidden states rather than on logits. Together they are 391 of
        // the 729 tensors, which is why not porting the tower is worth this much care.
        let ignored = published.subtracting(expected)
        #expect(ignored.count == 391)
        #expect(
            ignored.allSatisfy { $0.hasPrefix("visual.") || $0 == "lm_head.weight" },
            "unexpected leftovers: \(ignored.filter { !$0.hasPrefix("visual.") }.sorted())")
    }

    /// The tensor names in a sharded component's index.
    private static func indexedKeys(_ index: URL) throws -> Set<String> {
        struct Index: Decodable { let weightMap: [String: String] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Set(try decoder.decode(Index.self, from: Data(contentsOf: index)).weightMap.keys)
    }

    private static func expectedTransformerKeys(
        _ configuration: QwenImageTransformerConfiguration
    ) -> Set<String> {
        var keys: Set<String> = []
        for base in ["img_in", "proj_out", "norm_out.linear", "txt_in"] {
            keys.formUnion(["\(base).weight", "\(base).bias"])
        }
        keys.insert("txt_norm.weight")
        for index in 1...2 {
            let base = "time_text_embed.timestep_embedder.linear_\(index)"
            keys.formUnion(["\(base).weight", "\(base).bias"])
        }
        // Projections carry a bias; the query and key norms are RMS norms and do not.
        let biased = [
            "attn.to_q", "attn.to_k", "attn.to_v", "attn.to_out.0",
            "attn.add_q_proj", "attn.add_k_proj", "attn.add_v_proj", "attn.to_add_out",
            "img_mod.1", "txt_mod.1",
            "img_mlp.net.0.proj", "img_mlp.net.2", "txt_mlp.net.0.proj", "txt_mlp.net.2",
        ]
        let unbiased = ["attn.norm_q", "attn.norm_k", "attn.norm_added_q", "attn.norm_added_k"]
        for block in 0..<configuration.numLayers {
            let prefix = "transformer_blocks.\(block)"
            for name in biased { keys.formUnion(["\(prefix).\(name).weight", "\(prefix).\(name).bias"]) }
            for name in unbiased { keys.insert("\(prefix).\(name).weight") }
        }
        return keys
    }

    private static func expectedTextEncoderKeys(
        _ configuration: QwenImageTextEncoderConfiguration
    ) -> Set<String> {
        var keys: Set<String> = ["model.embed_tokens.weight", "model.norm.weight"]
        for layer in 0..<configuration.numHiddenLayers {
            let prefix = "model.layers.\(layer)"
            keys.formUnion([
                "\(prefix).input_layernorm.weight",
                "\(prefix).post_attention_layernorm.weight",
                "\(prefix).self_attn.o_proj.weight",
                "\(prefix).mlp.gate_proj.weight",
                "\(prefix).mlp.up_proj.weight",
                "\(prefix).mlp.down_proj.weight",
            ])
            // Qwen2.5 carries a bias on the query, key, and value projections, where Qwen3 does
            // not and instead norms each head. Getting this backwards is the single easiest way
            // to port the wrong attention.
            for projection in ["q_proj", "k_proj", "v_proj"] {
                keys.formUnion([
                    "\(prefix).self_attn.\(projection).weight",
                    "\(prefix).self_attn.\(projection).bias",
                ])
            }
        }
        return keys
    }
}
