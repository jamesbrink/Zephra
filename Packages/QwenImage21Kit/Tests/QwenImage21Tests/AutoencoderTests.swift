import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

@Suite("the RGBA autoencoder answers what diffusers answers")
struct AutoencoderTests {
    /// Doll's house, float32 through a handful of small convolutions.
    static let dollsHouseTolerance: Float = 1e-5
    /// The published model, float32 through 337.74 M parameters of 3 x 3 convolutions.
    /// Measured at 2.6e-4 on an encode and 4.8e-5 on a decode; a tenth of a unit of the -1 to 1
    /// pixel range is 0.1, so this is four orders below anything a picture would show.
    static let publishedTolerance: Float = 1e-3

    // MARK: The doll's house, which needs no release

    @Test("a doll's-house encode is the reference's, mode and all")
    func dollsHouseEncode() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let picture = VAEFixture.channelsLast(try #require(fixture["in.picture"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["out.latents"]))

        let latent = autoencoder.encode(picture)
        #expect(latent.shape == expected.shape, "16 x 16 at four halvings per stage: 4 x 4 x 8")
        #expect(Fixture.maxAbsoluteDifference(latent, expected) < Self.dollsHouseTolerance)
    }

    @Test("a doll's-house decode is the reference's, four channels wide")
    func dollsHouseDecode() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        // The reference decodes the restored latent, which is the normalised one put back.
        let normalization = QwenImage21LatentNormalization(
            mean: try #require(fixture["in.latentsMean"]).asArray(Float.self),
            std: try #require(fixture["in.latentsStd"]).asArray(Float.self))
        let normalized = VAEFixture.channelsLast(try #require(fixture["out.normalised"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["out.decoded"]))

        let picture = autoencoder.decode(normalization.denormalize(normalized))
        #expect(picture.dim(3) == 4, "RGBA out, which is the whole point of 2.1")
        #expect(picture.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(picture, expected) < Self.dollsHouseTolerance)
    }

    @Test("a decode is clamped to the pixel range, as the reference's _decode clamps it")
    func decodeIsClamped() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let wild = VAEFixture.channelsLast(try #require(fixture["out.latents"])) * 50
        let picture = autoencoder.decode(wild)
        #expect(picture.max().item(Float.self) <= 1)
        #expect(picture.min().item(Float.self) >= -1)
    }

    // MARK: The published model

    @Test(
        "the published encode is the reference's over a real RGBA picture",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedEncode() throws {
        let fixture = try Fixture.load("vae_real")
        let (autoencoder, configuration) = try VAEFixture.published()
        let picture = VAEFixture.channelsLast(try #require(fixture["real.picture"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["real.encoded"]))

        let latent = autoencoder.encode(picture)
        #expect(latent.shape == [1, 4, 4, configuration.zDim], "64 pixels over 16 is 4 cells")
        #expect(Fixture.maxAbsoluteDifference(latent, expected) < Self.publishedTolerance)
    }

    @Test(
        "the published decode is the reference's, alpha included",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedDecode() throws {
        let fixture = try Fixture.load("vae_real")
        let (autoencoder, _) = try VAEFixture.published()
        let latent = VAEFixture.channelsLast(try #require(fixture["real.latent"]))
        let expected = VAEFixture.channelsLast(try #require(fixture["real.decoded"]))

        let picture = autoencoder.decode(latent)
        #expect(picture.shape == [1, 64, 64, 4])
        #expect(Fixture.maxAbsoluteDifference(picture, expected) < Self.publishedTolerance)
    }
}
