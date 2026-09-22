import Foundation
import MLX

/// What one generation produced.
///
/// The PNG is what a host saves, and it is **RGBA**: 2.1's autoencoder decodes four channels
/// and the fourth is the picture's own straight alpha, written with `CGImageAlphaInfo.last`.
///
/// `latents` is the finished latent in the transformer's own space, `[1, tokens, zDim]`, which
/// is the reference pipeline's `output_type="latent"`. It is carried because the end-to-end
/// parity suite compares it against the reference's, and comparing latents rather than bytes is
/// what keeps that comparison about the port rather than about two PNG encoders.
public struct QwenImage21Result {
    /// The picture, as RGBA PNG bytes.
    public let png: Data
    /// Rendered width in pixels.
    public let width: Int
    /// Rendered height in pixels.
    public let height: Int
    /// The finished latent, `[1, tokens, zDim]`, before it was unpacked and decoded.
    public let latents: MLXArray

    public init(png: Data, width: Int, height: Int, latents: MLXArray) {
        self.png = png
        self.width = width
        self.height = height
        self.latents = latents
    }
}
