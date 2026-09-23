import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// The decoder in overlapping spatial tiles.
///
/// **A tile is an approximation.** Only the upsampling stages are tiled: `conv_in` and the mid
/// block, whose attention is one head over every cell, run whole first, because a tile that
/// attended to itself alone decoded as a different picture from its neighbours -- ghosted
/// rectangles in the alpha on every 16 GB Mac (2026-09-23). What is left is four
/// nearest-neighbour doublings with a 3 x 3 convolution after each, reaching further than the
/// quarter-tile cross-fade. Measured against the untiled decode of a real 16 x 16 latent: a
/// 12-cell tile is 38 dB and an 8-cell tile 26 (24 and 17 while the attention was tiled too),
/// and a tile at or above the latent's own size is the untiled decode exactly.
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
        "a real 12-cell tile keeps the shape and the range and stays within 35 dB of untiled",
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
        #expect(psnr > 35, Comment(rawValue: "tiled against untiled: \(psnr) dB"))
    }
}

/// What a 16 GB Mac actually runs: a 1024 picture, 64 cells an edge, decoded in the 32-cell
/// tile `QwenImage21RequestMapper` makes of the engine's 64.
@Suite("the decoder tiled as a 16 GB Mac tiles it")
struct TiledDecodeAtScaleTests {
    /// An opaque 1024 picture with detail everywhere: two crossed ramps and a ripple, so no
    /// tile of it is a flat field and each would attend to a different picture on its own.
    static func opaquePicture(size n: Int = 1024) -> MLXArray {
        let rows = MLXArray(Array(0..<n)).asType(.float32).reshaped([n, 1]) / Float(n - 1)
        let columns = MLXArray(Array(0..<n)).asType(.float32).reshaped([1, n]) / Float(n - 1)
        let red = MLX.broadcast(columns * 2 - 1, to: [n, n])
        let green = MLX.broadcast(rows * 2 - 1, to: [n, n])
        let blue = MLX.sin(rows * 37) * MLX.cos(columns * 23) * 0.8
        let alpha = MLXArray.ones([n, n])
        return MLX.stacked([red, green, blue, alpha], axis: -1)[.newAxis]
    }

    @Test(
        "an opaque 1024 picture tiled at 32 cells stays opaque and close to the untiled decode",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func opaqueStaysOpaque() throws {
        let (autoencoder, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        let latent = normalization.denormalize(
            normalization.normalize(autoencoder.encode(Self.opaquePicture())))
        #expect(latent.shape == [1, 64, 64, 64])

        let whole = autoencoder.decodeUntiled(latent)
        let tiled = autoencoder.decode(latent, tile: 32)
        let rgb = AutoencoderRoundTripTests.psnr(tiled[.ellipsis, 0..<3], whole[.ellipsis, 0..<3])
        let alpha = AutoencoderRoundTripTests.psnr(tiled[.ellipsis, 3...], whole[.ellipsis, 3...])
        // 250 of 255 is `QwenImage21Opacity`'s floor; in -1...1 that is 0.96.
        let lowest = tiled[.ellipsis, 3...].min().item(Float.self)
        let untiledLowest = whole[.ellipsis, 3...].min().item(Float.self)
        let note = "rgb \(rgb) dB, alpha \(alpha) dB, lowest alpha \(lowest) (untiled \(untiledLowest))"
        #expect(rgb > 30, Comment(rawValue: note))
        #expect(alpha > 30, Comment(rawValue: note))
        #expect(lowest > 0.96, Comment(rawValue: note))
    }
}
