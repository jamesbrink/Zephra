import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// The decoder in overlapping spatial tiles.
///
/// **A tile is an approximation, and on this decoder not a fine one.** Four nearest-neighbour
/// doublings with a 3 x 3 convolution after each mean one latent cell reaches a long way into
/// the picture, and `TiledDecode`'s overlap is a quarter of the tile, so a tile decoded on its
/// own is wrong near its edges over a wider band than the cross-fade covers. Measured against
/// the untiled decode of a real 16 x 16 latent: a 12-cell tile is 24 dB, an 8-cell tile 17 dB,
/// and a tile at or above the latent's own size is the untiled decode exactly. Over random
/// normal latents, which is the worst case there is, the mean absolute error falls from 0.048
/// at a 6-cell tile to 0.010 at a 24-cell tile on a range of 2.
///
/// So the tile this family ships with belongs well up that curve, and the backend picks it; the
/// figures are here so that pick is made against measurements rather than against a hope. What
/// this suite pins is the part that must be exact -- a tile that does not divide the latent
/// changes nothing at all -- and the shape and range of the part that is not.
@Suite("the decoder in spatial tiles")
struct TiledDecodeTests {
    @Test("a tile as wide as the latent is the plain decode, and a smaller one keeps its shape")
    func shapeAndIdentity() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let latent = VAEFixture.channelsLast(try #require(fixture["out.latents"]))  // 4 x 4

        let whole = autoencoder.decodeUntiled(latent)
        #expect(Fixture.maxAbsoluteDifference(autoencoder.decode(latent, tile: 4), whole) == 0)
        #expect(Fixture.maxAbsoluteDifference(autoencoder.decode(latent, tile: 9), whole) == 0)
        let tiled = autoencoder.decode(latent, tile: 2)
        #expect(tiled.shape == whole.shape)
        #expect(tiled.max().item(Float.self) <= 1)
        #expect(tiled.min().item(Float.self) >= -1)
    }

    @Test(
        "the real decoder tiled at or above the latent is exactly its untiled self",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedTileWiderThanTheLatent() throws {
        let (autoencoder, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        let latent = normalization.denormalize(
            normalization.normalize(
                autoencoder.encode(AutoencoderRoundTripTests.picture())))
        #expect(latent.shape == [1, 16, 16, 64])

        let whole = autoencoder.decodeUntiled(latent)
        #expect(whole.shape == [1, 256, 256, 4], "16 pixels a cell")
        #expect(Fixture.maxAbsoluteDifference(autoencoder.decode(latent, tile: 16), whole) == 0)
        #expect(Fixture.maxAbsoluteDifference(autoencoder.decode(latent, tile: 64), whole) == 0)
    }

    @Test(
        "a real 12-cell tile keeps the shape and the range and stays within 20 dB of untiled",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func publishedTiledApproximates() throws {
        let (autoencoder, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        let latent = normalization.denormalize(
            normalization.normalize(
                autoencoder.encode(AutoencoderRoundTripTests.picture())))

        let whole = autoencoder.decodeUntiled(latent)
        // Twelve cells over a sixteen-cell latent strides nine and blends three, so every seam
        // is a real cross-fade rather than one tile standing in for the picture.
        let tiled = autoencoder.decode(latent, tile: 12)
        #expect(tiled.shape == whole.shape)
        #expect(tiled.max().item(Float.self) <= 1)
        #expect(tiled.min().item(Float.self) >= -1)
        let psnr = AutoencoderRoundTripTests.psnr(tiled, whole)
        #expect(psnr > 20, Comment(rawValue: "tiled against untiled: \(psnr) dB"))
    }
}
