import Foundation
import MLX
import ZephraMLX

/// One frame of a Qwen-Image generation still in flight: the run's estimate of the finished
/// latent, pooled and decoded small.
///
/// The pooling happens on the unpacked latent rather than on the tokens: a token's 64 channels
/// are a 2x2 patch's cells stacked, so averaging tokens would mix a patch's corners with its
/// neighbours' and print a checkerboard.
public struct QwenImageLatentPreview: Sendable {
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// `width * height * 4` bytes, RGBA8, row-major, opaque.
    public let pixels: Data

    /// Decodes one estimate of the finished latent.
    ///
    /// - Parameters:
    ///   - tokens: `[1, tokens, 64]`, in the loop's own packed space. The loop passes its
    ///     estimate of the finished latent rather than the latent it holds; see
    ///     `QwenImageDenoiseLoop` for why that difference is the whole feature.
    ///   - latentHeight: the latent's rows, which is the image's height over 8.
    ///   - latentWidth: its columns.
    ///   - autoencoder: the loaded model's, which is the only decoder that means anything here.
    static func make(
        tokens: MLXArray,
        latentHeight: Int,
        latentWidth: Int,
        autoencoder: QwenImageAutoencoder
    ) -> QwenImageLatentPreview {
        let latents = QwenImageLatentPacking.unpack(
            tokens, height: latentHeight, width: latentWidth)
        let factor = LatentPreview.poolingFactor(height: latentHeight, width: latentWidth)
        let image = autoencoder.decodeUntiled(LatentPreview.pooled(latents, by: factor))
        MLX.eval(image)
        return QwenImageLatentPreview(
            width: image.dim(2), height: image.dim(1), pixels: LatentPreview.rgba8(image))
    }
}
