import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

@Suite("the latent upsampler reproduces the reference's doubling, statistics included")
struct LatentUpsamplerParityTests {
    /// The doll's house `Tools/dump_upsampler.py` builds: eight latent channels, sixty-four
    /// through, one block a stage. Sixty-four is the narrowest width at which GroupNorm's
    /// thirty-two groups hold more than one channel, so a wrongly grouped norm cannot pass.
    static let dollsHouse = LTX2UpsamplerConfiguration(inChannels: 8, midChannels: 64, blocksPerStage: 1)

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2LatentUpsampler {
        let upsampler = LTX2LatentUpsampler(dollsHouse)
        // The fixture's inputs and outputs sit under the same prefix as the weights.
        try upsampler.load(weights: fixture.filter {
            !$0.key.hasPrefix("spatial_upscaler_x2_v1_1.in.") && !$0.key.hasPrefix("spatial_upscaler_x2_v1_1.out.")
        })
        return upsampler
    }

    @Test("a denormalised latent doubles to the reference's within float32 noise")
    func networkMatchesTheReference() throws {
        let fixture = try Fixture.load("latent_upsampler")
        let upsampler = try Self.loaded(fixture)
        #expect(upsampler.dtype == .float32)

        let latent = try #require(fixture["spatial_upscaler_x2_v1_1.in.latent"])
        let expected = try #require(fixture["spatial_upscaler_x2_v1_1.out.latent"])
        let doubled = upsampler(latent.transposed(0, 2, 3, 4, 1)).transposed(0, 4, 1, 2, 3)
        #expect(doubled.shape == [1, 8, 3, 8, 12])
        #expect(doubled.shape == expected.shape)
        let difference = Fixture.maxAbsoluteDifference(doubled, expected)
        // Measured at 6e-6 on an M4 Max; float32 accumulation order is all that differs.
        #expect(difference < 1e-4, "max abs difference \(difference)")
    }

    @Test("a normalised latent is denormalised, doubled and normalised again as the pipelines do")
    func upsampleMatchesThePipelines() throws {
        let upsampler = try Self.loaded(try Fixture.load("latent_upsampler"))
        let fixture = try Fixture.load("latent_upsampler_normalized")
        let statistics = LTX2PerChannelStatistics(channels: 8)
        statistics.update(parameters: ModuleParameters.unflattened([
            "mean": try #require(fixture["spatial_upscaler_x2_v1_1.in.mean"]),
            "std": try #require(fixture["spatial_upscaler_x2_v1_1.in.std"]),
        ]))

        let normalized = try #require(fixture["spatial_upscaler_x2_v1_1.in.normalized"])
        let expected = try #require(fixture["spatial_upscaler_x2_v1_1.out.normalized"])
        let doubled = upsampler.upsample(normalized, statistics: statistics)
        #expect(doubled.shape == [1, 8, 3, 8, 12])
        #expect(doubled.dtype == .float32)
        let difference = Fixture.maxAbsoluteDifference(doubled, expected)
        // Measured at 9e-6 on an M4 Max.
        #expect(difference < 1e-4, "max abs difference \(difference)")
    }

    @Test("a tree with the statistics left at the identity doubles to something else")
    func statisticsMatter() throws {
        let upsampler = try Self.loaded(try Fixture.load("latent_upsampler"))
        let fixture = try Fixture.load("latent_upsampler_normalized")
        let normalized = try #require(fixture["spatial_upscaler_x2_v1_1.in.normalized"])
        let expected = try #require(fixture["spatial_upscaler_x2_v1_1.out.normalized"])
        let identity = LTX2PerChannelStatistics(channels: 8)
        let doubled = upsampler.upsample(normalized, statistics: identity)
        #expect(Fixture.maxAbsoluteDifference(doubled, expected) > 1e-2)
    }

    @Test("a one-frame latent doubles to one frame: time is zero-padded, never stretched")
    func singleFrame() throws {
        let fixture = try Fixture.load("latent_upsampler")
        let upsampler = try Self.loaded(fixture)
        let latent = try #require(fixture["spatial_upscaler_x2_v1_1.in.latent"])[0..., 0..., 0..<1]
        let doubled = upsampler.upsample(latent, statistics: LTX2PerChannelStatistics(channels: 8))
        #expect(doubled.shape == [1, 8, 1, 8, 12])
    }

    @Test("the pixel shuffle puts the height offset before the width offset")
    func shuffleOrder() {
        // Two output channels, factor 2x2: input channel c·4 + h·2 + w.
        let x = MLXArray(Array(0..<8).map(Float.init), [1, 1, 1, 8])
        let shuffled = LTX2SpatialPixelShuffle.shuffled(x)
        #expect(shuffled.shape == [1, 2, 2, 2])
        // Row 1, column 0, channel 0 is input channel 0·4 + 1·2 + 0 = 2.
        #expect(shuffled[0, 1, 0, 0].item(Float.self) == 2)
        // Row 0, column 1, channel 1 is input channel 1·4 + 0·2 + 1 = 5.
        #expect(shuffled[0, 0, 1, 1].item(Float.self) == 5)
    }

    @Test("the pack's config reads to the published configuration and refuses another head")
    func configuration() throws {
        let published = """
            {"config": {"_class_name": "LatentUpsampler", "in_channels": 128, "mid_channels": 1024,
             "num_blocks_per_stage": 4, "dims": 3, "spatial_upsample": true, "temporal_upsample": false,
             "spatial_scale": 2.0, "rational_resampler": false}}
            """
        let file = FileManager.default.temporaryDirectory.appending(path: "upsampler-\(UUID().uuidString).json")
        try published.data(using: .utf8)!.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try LTX2UpsamplerConfiguration(readingFrom: file) == .x2)

        try published.replacingOccurrences(of: "\"rational_resampler\": false", with: "\"rational_resampler\": true")
            .data(using: .utf8)!.write(to: file)
        #expect(throws: LTX2ConfigurationError.self) { try LTX2UpsamplerConfiguration(readingFrom: file) }
    }
}
