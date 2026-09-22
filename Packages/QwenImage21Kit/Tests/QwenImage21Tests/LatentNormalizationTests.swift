import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

@Suite("the latent's statistics stand between the autoencoder's space and the transformer's")
struct LatentNormalizationTests {
    @Test("normalising is the reference's (z - mean) / std, channel by channel")
    func normalizeIsTheReferences() throws {
        let fixture = try Fixture.load("vae")
        let normalization = QwenImage21LatentNormalization(
            mean: try #require(fixture["in.latentsMean"]).asArray(Float.self),
            std: try #require(fixture["in.latentsStd"]).asArray(Float.self))
        let latent = VAEFixture.channelsLast(try #require(fixture["out.latents"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["out.normalised"]))
        #expect(Fixture.maxAbsoluteDifference(normalization.normalize(latent), expected) < 1e-5)
    }

    @Test("denormalising undoes it")
    func roundTrips() {
        let normalization = QwenImage21LatentNormalization(
            mean: [1, -2, 0.5], std: [2, 0.5, 4])
        let latent = MLXArray((0..<12).map(Float.init), [1, 2, 2, 3])
        let normalized = normalization.normalize(latent)
        // Channel 1 at (0, 0) is 1: (1 - -2) / 0.5 = 6.
        #expect(normalized[0, 0, 0, 1].item(Float.self) == 6)
        #expect(Fixture.maxAbsoluteDifference(normalization.denormalize(normalized), latent) < 1e-6)
    }

    @Test(
        "the statistics are read from the published config, all sixty-four of each",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedStatistics() throws {
        let fixture = try Fixture.load("vae_real")
        let (_, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        #expect(normalization.mean.count == 64)
        #expect(normalization.std.count == 64)
        #expect(
            Fixture.maxAbsoluteDifference(
                MLXArray(normalization.mean), try #require(fixture["config.latentsMean"])) < 1e-6)
        #expect(
            Fixture.maxAbsoluteDifference(
                MLXArray(normalization.std), try #require(fixture["config.latentsStd"])) < 1e-6)
    }

    @Test(
        "the published encode, normalised, is what the reference hands the transformer",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedEncodeNormalized() throws {
        let fixture = try Fixture.load("vae_real")
        let (autoencoder, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        let picture = VAEFixture.channelsLast(try #require(fixture["real.picture"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["real.normalised"]))
        let normalized = normalization.normalize(autoencoder.encode(picture))
        #expect(
            Fixture.maxAbsoluteDifference(normalized, expected)
                < AutoencoderTests.publishedTolerance)
    }
}
