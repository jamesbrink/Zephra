import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// The tower's 351 published tensors, and the shapes that say which of the four mergers is
/// which.
///
/// 351 is three at the front — the patch kernel, its bias and the position table — twelve for
/// each of the 27 blocks, and six for each of the four mergers. The decoder's 397 and these
/// make 748; `lm_head.weight` and the final norm are the other two of the release's 750.
extension WeightKeyCoverageTests {
    @Test(
        "the tower's 351 tensors are exactly the ones this architecture implies",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func visionTowerKeys() throws {
        let vision = try Self.publishedTextEncoderConfiguration().vision
        let published = try Self.indexedKeys(
            try #require(SnapshotUnderTest.qwenImage21.release)
                .appending(path: "text_encoder/model.safetensors.index.json"))
            .filter { $0.hasPrefix(Qwen3VLVisionWeights.prefix) }

        Self.expectNamesMatch(
            published: Set(published), expected: Qwen3VLVisionWeights.expectedKeys(vision))
        #expect(published.count == 3 + 27 * 12 + 4 * 6)
        #expect(published.count == 351)
        #expect(vision.depth == 27)
        #expect(vision.deepstackVisualIndexes == [8, 16, 24])
    }

    @Test(
        "the merger norms say which merges before the shuffle and which after",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func theMergerNormsAreTheTell() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let vision = try Self.publishedTextEncoderConfiguration().vision
        let shapes = try Self.shardedShapes(
            snapshot.appending(path: "text_encoder"),
            named: ["model.visual.merger.norm.weight"]
                + (0..<3).map { "model.visual.deepstack_merger_list.\($0).norm.weight" }
                + ["model.visual.patch_embed.proj.weight", "model.visual.pos_embed.weight"])

        // 1152 against 4608 is the whole of `use_postshuffle_norm`, and nothing else in the
        // checkpoint distinguishes the four mergers.
        #expect(shapes["model.visual.merger.norm.weight"] == [vision.hiddenSize])
        for index in 0..<3 {
            #expect(
                shapes["model.visual.deepstack_merger_list.\(index).norm.weight"]
                    == [vision.hiddenSize * vision.spatialMergeSize * vision.spatialMergeSize])
        }

        // The Conv3d kernel and the square position table, both of which the port reshapes.
        #expect(
            shapes["model.visual.patch_embed.proj.weight"]
                == [vision.hiddenSize, 3, vision.temporalPatchSize, vision.patchSize, vision.patchSize])
        #expect(shapes["model.visual.pos_embed.weight"] == [2304, vision.hiddenSize])
        #expect(2304 == 48 * 48)
    }

}
