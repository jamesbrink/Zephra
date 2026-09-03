import Foundation
import Testing
import ZephraQuantization

@testable import Flux2

/// Every tensor the published snapshot ships, accounted for before a module is written.
///
/// This is the cheap way to be certain a module tree matches the weights it will be handed: the
/// expected names and shapes below are derived from the configuration files, and the safetensors
/// headers say what is actually in the snapshot. A name on one side and not the other is a
/// rename, a miscounted block, or a component this port has forgotten -- each of which is hours
/// of parity debugging if it is found later.
///
/// Nothing here reads a weight. Headers and index files only, so eight gigabytes are checked in
/// well under a second.
@Suite("Every published tensor is accounted for")
struct WeightKeyCoverageTests {
    @Test(
        "the encoder loads the 27 layers it taps and leaves the rest of Qwen3-4B on disk",
        .enabled(if: SnapshotUnderTest.isPresent))
    func textEncoderKeys() throws {
        let snapshot = try #require(SnapshotUnderTest.directory)
        let configuration = try Flux2Configuration(readingFrom: snapshot)
        let published = try Self.indexedKeys(
            snapshot.appending(path: "text_encoder/model.safetensors.index.json"))
        let expected = Self.expectedTextEncoderKeys(configuration.textEncoder)

        #expect(published.count == 398)
        #expect(
            expected.subtracting(published).isEmpty,
            Comment(rawValue: "expected but absent: \(expected.subtracting(published).sorted())"))

        // The leftover is the whole of the saving. Layers 27 through 35 and the final norm are
        // 100 of the 398 tensors and about two gigabytes, and the conditioning never reaches
        // them. `lm_head` is not even published: `tie_word_embeddings` is true, and klein reads
        // hidden states rather than logits.
        let leftover = published.subtracting(expected)
        let unreached = Set((27..<36).flatMap { Self.textEncoderLayerKeys($0) } + ["model.norm.weight"])
        #expect(leftover == unreached, Comment(rawValue: "unexpected leftovers: \(leftover.subtracting(unreached).sorted())"))
        #expect(!published.contains { $0.contains("lm_head") })
    }

    @Test(
        "the transformer's 169 tensors are exactly the ones this architecture implies",
        .enabled(if: SnapshotUnderTest.isPresent))
    func transformerTensors() throws {
        let snapshot = try #require(SnapshotUnderTest.directory)
        let configuration = try Flux2Configuration(readingFrom: snapshot)
        let published = try Self.headerShapes(
            snapshot.appending(path: "transformer/diffusion_pytorch_model.safetensors"))
        let expected = Self.expectedTransformerTensors(configuration.transformer)

        #expect(published.count == 169)
        Self.expectNamesMatch(published: Set(published.keys), expected: Set(expected.keys))
        Self.expectShapesMatch(published: published, expected: expected)
    }

    @Test(
        "the autoencoder's 251 tensors are exactly the ones this architecture implies",
        .enabled(if: SnapshotUnderTest.isPresent))
    func autoencoderTensors() throws {
        let snapshot = try #require(SnapshotUnderTest.directory)
        let configuration = try Flux2Configuration(readingFrom: snapshot)
        let published = try Self.headerShapes(
            snapshot.appending(path: "vae/diffusion_pytorch_model.safetensors"))

        #expect(published.count == 251)
        Self.expectNamesMatch(
            published: Set(published.keys),
            expected: Self.expectedAutoencoderKeys(configuration.vae))

        // The latent normalisation, which is where FLUX.2 differs from every other diffusers
        // autoencoder: running statistics over the packed 128-channel latent, no affine pair,
        // and a scalar count that has no place in a module tree.
        #expect(published["bn.num_batches_tracked"] == [])
        #expect(published["bn.running_mean"] == [configuration.vae.packedChannels])
        #expect(published["bn.running_var"] == [configuration.vae.packedChannels])
        #expect(published.keys.filter { $0.hasPrefix("bn.") }.count == 3)

        // The four convolutions at the ends, where a transposed axis would be silent.
        #expect(published["quant_conv.weight"] == [64, 64, 1, 1])
        #expect(published["post_quant_conv.weight"] == [32, 32, 1, 1])
        #expect(published["encoder.conv_in.weight"] == [128, 3, 3, 3])
        #expect(published["decoder.conv_out.weight"] == [3, 128, 3, 3])

        // Every convolution in either tower carries a bias, which is why the port can build
        // them all the same way.
        let convolutions = published.filter {
            ($0.key.hasPrefix("encoder.") || $0.key.hasPrefix("decoder."))
                && $0.key.hasSuffix(".weight") && $0.value.count == 4
        }
        let unbiased = convolutions.keys.filter {
            published[$0.replacingOccurrences(of: ".weight", with: ".bias")] == nil
        }
        #expect(unbiased.isEmpty, Comment(rawValue: "no bias beside: \(unbiased.sorted())"))
    }

    /// The tensor names in a sharded component's index.
    static func indexedKeys(_ index: URL) throws -> Set<String> {
        struct Index: Decodable { let weightMap: [String: String] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Set(try decoder.decode(Index.self, from: Data(contentsOf: index)).weightMap.keys)
    }

    /// Every tensor in a single-file component, by name, with its shape and none of its bytes.
    static func headerShapes(_ file: URL) throws -> [String: [Int]] {
        let header = try SafeTensorsHeader(contentsOf: file)
        return Dictionary(uniqueKeysWithValues: header.entries.map { ($0.name, $0.shape) })
    }

    static func expectNamesMatch(published: Set<String>, expected: Set<String>) {
        let absent = expected.subtracting(published)
        let unaccounted = published.subtracting(expected)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted())"))
        #expect(
            unaccounted.isEmpty,
            Comment(rawValue: "present but unaccounted for: \(unaccounted.sorted())"))
    }

    static func expectShapesMatch(published: [String: [Int]], expected: [String: [Int]]) {
        let wrong = expected.compactMap { name, shape -> String? in
            guard let actual = published[name], actual != shape else { return nil }
            return "\(name) is \(actual), expected \(shape)"
        }
        #expect(wrong.isEmpty, Comment(rawValue: wrong.sorted().joined(separator: "; ")))
    }
}
