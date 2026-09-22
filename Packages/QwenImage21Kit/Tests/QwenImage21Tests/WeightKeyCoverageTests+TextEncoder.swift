import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// The text encoder's 750 published tensors against what the decoder stack and the tower
/// between them build.
///
/// The release ships one component here and it is two models: `model.language_model.*` is the
/// 36-layer decoder and `model.visual.*` is the 27-block tower, with `lm_head.weight` beside
/// them. Two tensors are left on disk on purpose and this is where that is claimed rather than
/// inferred, since a tree that has forgotten a tensor and an expectation that has forgotten the
/// same one agree with each other.
extension WeightKeyCoverageTests {
    @Test(
        "the 750 published tensors are the decoder, the tower, and the head neither one loads",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func textEncoderKeys() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let configuration = try Self.publishedTextEncoderConfiguration()
        let published = try Self.indexedKeys(
            snapshot.appending(path: "text_encoder/model.safetensors.index.json"))

        #expect(published.count == 750)

        // 397 decoder tensors: the embedding table and eleven a layer over 36 layers.
        let decoder = Qwen3VLTextWeights.expectedKeys(layers: configuration.text.numHiddenLayers)
        #expect(decoder.count == 1 + 36 * 11)
        let absent = decoder.subtracting(published)
        #expect(absent.isEmpty, Comment(rawValue: "expected but absent: \(absent.sorted())"))

        // Everything else is the tower's 351, which `WeightKeyCoverageTests+Vision` claims one
        // by one, and the two tensors neither model loads.
        let rest = published.subtracting(decoder).subtracting(Qwen3VLTextWeights.omitted)
        #expect(rest.count == 351)
        #expect(rest.allSatisfy { $0.hasPrefix(Qwen3VLTextWeights.towerPrefix) })
        #expect(decoder.count + rest.count + Qwen3VLTextWeights.omitted.count == 750)
    }

    @Test(
        "the two tensors this port never loads are in the shards, so a pack must exclude them",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func theOmittedTensorsAreReallyThere() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let published = try Self.indexedKeys(
            snapshot.appending(path: "text_encoder/model.safetensors.index.json"))

        // `tie_word_embeddings` is false, so `lm_head.weight` is a real 622-million-parameter
        // tensor rather than a view of the embedding table: 1.24 GB that has to be named to be
        // left out. The final norm is the one the pipeline hooks away.
        for key in Qwen3VLTextWeights.omitted {
            #expect(published.contains(key), Comment(rawValue: "\(key) is not in the release"))
        }
        #expect(Qwen3VLTextWeights.sanitized(["lm_head.weight": MLXArray(0)]).isEmpty)
    }

    @Test(
        "the decoder's shapes are grouped-query 32 to 8 over a stated head width of 128",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func theDecoderShapes() throws {
        let configuration = try Self.publishedTextEncoderConfiguration()
        let text = configuration.text

        #expect(text.numAttentionHeads == 32 && text.numKeyValueHeads == 8)
        #expect(text.headDim == 128)
        // Stated rather than derived, and here it agrees: 4096 over 32 is 128. The tower is
        // where deriving it would be wrong — 1152 over 16 is 72 — and both are read the same
        // way so neither can drift.
        #expect(text.hiddenSize / text.numAttentionHeads == text.headDim)
        #expect(configuration.vision.headDim == 72)
        #expect(text.ropeTheta == 5_000_000)
        #expect(text.ropeScaling.mropeSection == [24, 20, 20])
        #expect(text.ropeScaling.mropeInterleaved)
    }
}
