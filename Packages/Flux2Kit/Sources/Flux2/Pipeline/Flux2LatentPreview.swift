import Foundation
import MLX
import ZephraMLX

/// One frame of a klein generation still in flight: the run's estimate of the finished latent,
/// pooled and decoded small.
///
/// The pooling happens between the two halves of `decodePacked`, on the unpacked latent rather
/// than on the tokens: a token's 128 channels are four latent cells stacked, so averaging tokens
/// would mix a patch's corners with its neighbours' and print a checkerboard.
public struct Flux2LatentPreview: Sendable {
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// `width * height * 4` bytes, RGBA8, row-major, straight alpha; 255 everywhere for a
    /// model that makes no transparency.
    public let pixels: Data

    /// Decodes one estimate of the finished latent.
    ///
    /// - Parameters:
    ///   - tokens: `[1, packedHeight * packedWidth, 128]`, in the loop's own packed space. The
    ///     loop passes its estimate of the finished latent rather than the latent it holds; see
    ///     `Flux2Pipeline+Denoise.swift` for why that difference is the whole feature.
    ///   - packedHeight: rows of the packed grid, which is the image's height over 16.
    ///   - packedWidth: columns of it.
    ///   - autoencoder: the loaded model's, which is the only decoder that means anything here.
    static func make(
        tokens: MLXArray,
        packedHeight: Int,
        packedWidth: Int,
        autoencoder: Flux2Autoencoder
    ) throws -> Flux2LatentPreview {
        let latents = autoencoder.unpacked(
            Flux2LatentPacking.grid(tokens, height: packedHeight, width: packedWidth))
        let factor = LatentPreview.poolingFactor(
            height: latents.dim(2), width: latents.dim(3))
        let image = autoencoder.decodeUntiled(LatentPreview.pooled(latents, by: factor))
        MLX.eval(image)
        return Flux2LatentPreview(
            width: image.dim(2), height: image.dim(1),
            pixels: try LatentPreview.rgba8(image))
    }
}
