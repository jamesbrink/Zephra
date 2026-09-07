import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the real encoder's tensors are exactly the tree's parameters")
struct VAEEncoderWeightKeyTests {
    /// Every tensor name and shape in `vae_encoder.safetensors` of `mlx-community/ltx-2.5-mlx`,
    /// read from the file's header on 2026-09-06 and committed as a list rather than as weights,
    /// so the layout is pinned without 638 megabytes in the repository.
    static func published() throws -> [String: [Int]] {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/vae_encoder_keys.json"))
        return try JSONDecoder().decode([String: [Int]].self, from: Data(contentsOf: url))
    }

    @Test("the ltx25 layout's parameter paths and shapes match the published header exactly")
    func keysAndShapes() throws {
        let published = try Self.published()
        let tree = LTX2VideoEncoder(.ltx25).parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[LTX2VAEWeights.encoderCheckpointName(of: $1.0)] = $1.1.shape
        }
        #expect(Set(tree.keys) == Set(published.keys))
        #expect(Set(tree.keys).subtracting(published.keys).isEmpty)
        #expect(Set(published.keys).subtracting(tree.keys).isEmpty)
        for (key, shape) in published {
            #expect(tree[key] == shape, "\(key)")
        }
        #expect(published.count == 86)
    }

    @Test("the statistics are renamed at the door, since the tree cannot spell the pack's names")
    func statisticsAreRenamed() throws {
        let published = try Self.published()
        #expect(published["vae_encoder.per_channel_statistics._mean_of_means"] == [128])
        #expect(published["vae_encoder.per_channel_statistics._std_of_means"] == [128])
        // mlx-swift drops any parameter key beginning with an underscore, so the tree holds
        // them without one and the rename runs both ways.
        #expect(
            LTX2VAEWeights.encoderCheckpointName(of: "per_channel_statistics.mean_of_means")
                == "vae_encoder.per_channel_statistics._mean_of_means")
        #expect(
            LTX2VAEWeights.encoderCheckpointName(of: "conv_in.conv.weight")
                == "vae_encoder.conv_in.conv.weight")
        let renamed = LTX2VAEWeights.sanitizedEncoder([
            "vae_encoder.per_channel_statistics._std_of_means": MLXArray.zeros([128]),
            "vae_decoder.per_channel_statistics.std": MLXArray.zeros([128]),
        ])
        #expect(Array(renamed.keys) == ["per_channel_statistics.std_of_means"])
    }

    @Test("the third stage holds four blocks, not the diffusers constructor's six")
    func theThirdStageIsFourBlocks() {
        #expect(LTX2VideoEncoderLayout.ltx25.stages.map(\.blocks) == [4, 6, 4, 2, 2])
        #expect(LTX2VideoEncoderLayout.ltx25.stages.map(\.channels) == [128, 256, 512, 1024, 1024])
    }

    @Test("the layout's arithmetic gives the eight-times-plus-one frames and 32 pixels a cell")
    func compression() {
        let layout = LTX2VideoEncoderLayout.ltx25
        #expect(layout.latentFrames(forPixelFrames: 1) == 1)
        #expect(layout.latentFrames(forPixelFrames: 49) == 7)
        #expect(layout.latentFrames(forPixelFrames: 121) == 16)
        #expect(layout.latentCells(forPixels: 768) == 24)
        #expect(layout.latentCells(forPixels: 512) == 16)
    }
}
