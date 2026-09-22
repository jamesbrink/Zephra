import Foundation
import MLX
import Testing

@testable import QwenImage21

/// The vision tower against the reference, weights and all, at doll's-house size.
///
/// What it pins: the Conv3d patch embedding run as a linear over its own flattened receptive
/// field, the interpolated position table added before the first block, the fused `qkv` with
/// bias, the tanh GELU in the blocks against the exact GELU in the mergers, the tower's own
/// axial rotary, the two-by-two merge, and — the part that is invisible in the output — the
/// three DeepStack taps.
@Suite("The vision tower reproduces the reference's slots and DeepStack taps")
struct VisionTowerTests {
    @Test("the merged slots match the reference")
    func theSlotsMatch() throws {
        let fixture = try Fixture.load("vision")
        let tower = try Qwen3VLDollHouse.visionTower(fixture, prefix: "visual.")
        let features = tower(
            try #require(fixture["tower.in.pixels"]), grid: Qwen3VLImageGrid(rows: 4, columns: 4))
        let reference = try #require(fixture["tower.out.slots"])

        #expect(features.slots.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(features.slots, reference)
        #expect(difference < 1e-4, Comment(rawValue: "the slots differ by \(difference)"))
    }

    @Test("all three DeepStack taps match, and they are not the tower's own output")
    func theTapsMatch() throws {
        let fixture = try Fixture.load("vision")
        let tower = try Qwen3VLDollHouse.visionTower(fixture, prefix: "visual.")
        let features = tower(
            try #require(fixture["tower.in.pixels"]), grid: Qwen3VLImageGrid(rows: 4, columns: 4))

        #expect(features.deepStack.count == 3)
        for (index, tap) in features.deepStack.enumerated() {
            let reference = try #require(fixture["tower.out.deepstack\(index)"])
            let difference = Fixture.maxAbsoluteDifference(tap, reference)
            #expect(difference < 1e-4, Comment(rawValue: "tap \(index) differs by \(difference)"))
        }

        // Each tap runs through a merger of its own, over a different block's output, so none
        // of them is the tower's `merger` answer. A port that returned the slots three times
        // would pass every shape check there is.
        for tap in features.deepStack {
            #expect(Fixture.maxAbsoluteDifference(tap, features.slots) > 1e-3)
        }
    }

    @Test("every tower tensor is claimed, and only the patch kernel changes shape")
    func theWeightNamesLineUp() throws {
        let fixture = try Fixture.load("vision")
        let configuration = try Qwen3VLDollHouse.configuration().vision
        let tower = Qwen3VLVisionTower(configuration)

        let ours = Set(tower.parameters().flattened().map(\.0))
        let expected = Set(Qwen3VLDollHouse.weights(fixture, prefix: "visual.").keys)
        #expect(ours == expected, Comment(rawValue: "mismatch: \(ours.symmetricDifference(expected).sorted())"))

        // `[32, 3, 2, 4, 4]` on disk against `[32, 96]` in the tree, and no permute between
        // them: the kernel's axis order is already the order a patch vector is laid out in.
        let stored = try #require(fixture["visual.patch_embed.proj.weight"])
        #expect(stored.shape == [32, 3, 2, 4, 4])
        let sanitized = Qwen3VLVisionWeights.sanitized([
            Qwen3VLVisionWeights.prefix + Qwen3VLVisionWeights.patchKernel: stored
        ])
        #expect(sanitized[Qwen3VLVisionWeights.patchKernel]?.shape == [32, 96])
    }

    @Test("the merger normalises before the shuffle and a DeepStack merger after it")
    func theMergerNormsDifferInShape() throws {
        let configuration = try Qwen3VLDollHouse.configuration().vision
        let before = Qwen3VLVisionMerger(configuration, afterShuffle: false)
        let after = Qwen3VLVisionMerger(configuration, afterShuffle: true)

        // The norm's own shape is the only tell for `use_postshuffle_norm`, and getting it the
        // wrong way round normalises across four patches that should have been apart.
        #expect(before.norm.weight?.shape == [configuration.hiddenSize])
        #expect(after.norm.weight?.shape == [configuration.hiddenSize * 4])
    }
}
