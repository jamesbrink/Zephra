import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// A picture through the published autoencoder and back, judged as a picture.
///
/// The parity suites say this port computes what the reference computes; they would say so just
/// as loudly if both were nonsense. This says the model is actually an autoencoder: a 256 x 256
/// RGBA picture comes back recognisable where it is visible, and the transparent half of it
/// comes back transparent. It is the one test here that would catch a port that agreed with the
/// reference because both were reading the same wrong weights.
///
/// **Colour under a transparent pixel is not carried, and that is the model and not this port.**
/// Measured on this picture: the opaque half comes back at 38 to 49 dB a channel and the alpha
/// channel at 51, while the fully transparent half's colour comes back at 4 to 8 dB. An RGBA
/// autoencoder spending latent capacity on colour nobody can see would be spending it wrongly,
/// so the picture is judged where the picture is.
@Suite("a picture survives the published round trip, alpha included")
struct AutoencoderRoundTripTests {
    static let size = 256
    /// Columns either side of the alpha edge left out of both readings: a hard step is the one
    /// thing a sixteen-fold compression cannot put back exactly, and the seam is not what
    /// either half is about.
    static let seam = 8

    /// Gradients and one solid shape: the structure an autoencoder is for.
    ///
    /// Not noise and not a chirp. A 16x autoencoder carries a 256 x 256 picture in 256 latent
    /// cells, so a pattern at the pixel scale is thrown away however right the port is -- a
    /// fixed chirp here read 10 dB on the visible half where these gradients read 49.
    ///
    /// The left half is fully transparent and the right fully opaque, with a hard edge down the
    /// middle, which is what the alpha assertions read.
    static func picture() -> MLXArray {
        let n = size
        let rows = MLXArray(Array(0..<n)).asType(.float32).reshaped([n, 1]) / Float(n - 1)
        let columns = MLXArray(Array(0..<n)).asType(.float32).reshaped([1, n]) / Float(n - 1)
        let red = MLX.broadcast(columns * 2 - 1, to: [n, n])
        let green = MLX.broadcast(rows * 2 - 1, to: [n, n])
        // A disc a third of the frame across, centred: one hard edge and two flat fields.
        let radius = MLX.square(rows - 0.5) + MLX.square(columns - 0.5)
        let blue = MLX.where(radius .< 0.04, MLXArray(Float(0.8)), MLXArray(Float(-0.7)))
        let alpha = MLXArray.zeros([n, n]) - 1
        alpha[0..., (n / 2)...] = MLXArray(Float(1))
        return MLX.stacked(
            [red, green, MLX.broadcast(blue, to: [n, n]), alpha], axis: -1)[.newAxis]
    }

    /// Peak signal to noise between two slices of the -1 to 1 pixel range, whose peak is 2.
    static func psnr(_ a: MLXArray, _ b: MLXArray) -> Float {
        20 * log10(2 / MLX.mean(MLX.square(a - b)).item(Float.self).squareRoot())
    }

    @Test(
        "the visible half comes back above 30 dB and the transparent half comes back transparent",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func roundTrip() throws {
        let (autoencoder, configuration) = try VAEFixture.published()
        let normalization = QwenImage21LatentNormalization(configuration)
        let original = Self.picture()

        let latent = normalization.normalize(autoencoder.encode(original))
        #expect(latent.shape == [1, 16, 16, 64], "256 pixels over 16 is 16 cells")
        let restored = autoencoder.decode(normalization.denormalize(latent))
        #expect(restored.shape == original.shape)

        // The picture, where the picture is: colour over the opaque half.
        let opaque = (Self.size / 2 + Self.seam)...
        let colour = Self.psnr(
            restored[0, 0..., opaque, 0..<3], original[0, 0..., opaque, 0..<3])
        #expect(colour > 30, Comment(rawValue: "visible colour PSNR \(colour) dB"))

        // Alpha everywhere, since the edge is what it is about.
        let alpha = Self.psnr(restored[0, 0..., 0..., 3], original[0, 0..., 0..., 3])
        #expect(alpha > 30, Comment(rawValue: "alpha PSNR \(alpha) dB"))

        // And alpha read as the two fields it is, rather than as an average that a uniformly
        // half-opaque picture would also pass.
        let transparentSide = MLX.mean(
            restored[0, 0..., 0..<(Self.size / 2 - Self.seam), 3]).item(Float.self)
        let opaqueSide = MLX.mean(restored[0, 0..., opaque, 3]).item(Float.self)
        #expect(transparentSide < -0.9, Comment(rawValue: "transparent half \(transparentSide)"))
        #expect(opaqueSide > 0.9, Comment(rawValue: "opaque half \(opaqueSide)"))
    }
}
