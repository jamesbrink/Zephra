import Foundation
import MLX

/// Turns a latent image into the token sequence the transformer reads, and back.
///
/// The transformer sees one token per 2x2 latent patch, with the patch's four cells stacked into
/// the channel dimension — which is why the config's `in_channels` is 64 for a 16-channel latent.
/// The axis order below is the whole of it, and getting it wrong scrambles the image into
/// plausible-looking noise rather than failing.
public enum QwenImageLatentPacking {
    /// Latent cells along each edge of a patch.
    public static let patchSize = 2

    /// Packs `[batch, channels, height, width]` into `[batch, tokens, channels * 4]`.
    public static func pack(_ latents: MLXArray) -> MLXArray {
        let (batch, channels, height, width) = dimensions(of: latents)
        let patch = patchSize
        return
            latents
            .reshaped([batch, channels, height / patch, patch, width / patch, patch])
            .transposed(0, 2, 4, 1, 3, 5)
            .reshaped([batch, (height / patch) * (width / patch), channels * patch * patch])
    }

    /// Unpacks `[batch, tokens, channels * 4]` back to `[batch, channels, height, width]`, where
    /// `height` and `width` are in latent cells.
    public static func unpack(_ tokens: MLXArray, height: Int, width: Int) -> MLXArray {
        let patch = patchSize
        let batch = tokens.shape[0]
        let channels = tokens.shape[2] / (patch * patch)
        return
            tokens
            .reshaped([batch, height / patch, width / patch, channels, patch, patch])
            .transposed(0, 3, 1, 4, 2, 5)
            .reshaped([batch, channels, height, width])
    }

    /// How many tokens an image of this latent size becomes. The scheduler's dynamic shift is a
    /// function of this, so it is worth having a name.
    public static func tokenCount(latentHeight: Int, latentWidth: Int) -> Int {
        (latentHeight / patchSize) * (latentWidth / patchSize)
    }

    private static func dimensions(of latents: MLXArray) -> (Int, Int, Int, Int) {
        let shape = latents.shape
        return (shape[0], shape[1], shape[2], shape[3])
    }
}
