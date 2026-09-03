import Foundation
import MLX

/// Turns a latent image into the token sequence the transformer reads, and back.
///
/// Two moves, kept apart because the reference keeps them apart and the batch-norm statistics
/// sit between them. `patchify` stacks each 2x2 patch's cells into the channel axis, so a
/// 32-channel latent becomes a 128-channel one at half the size; that is the space the
/// normalisation statistics are stated in. `tokens` then flattens the grid into a sequence,
/// row-major. The axis order in `patchify` is the whole of it: it is channel-major, with the
/// four cells of a patch adjacent for each channel, and getting it wrong scrambles the image
/// into plausible-looking noise rather than failing.
public enum Flux2LatentPacking {
    /// Latent cells along each edge of a patch.
    public static let patchSize = 2

    /// `[batch, channels, height, width]` to `[batch, channels * 4, height / 2, width / 2]`.
    public static func patchify(_ latents: MLXArray) -> MLXArray {
        let (batch, channels, height, width) = dimensions(of: latents)
        let patch = patchSize
        return
            latents
            .reshaped([batch, channels, height / patch, patch, width / patch, patch])
            .transposed(0, 1, 3, 5, 2, 4)
            .reshaped([batch, channels * patch * patch, height / patch, width / patch])
    }

    /// `[batch, channels * 4, height, width]` back to `[batch, channels, height * 2, width * 2]`.
    public static func unpatchify(_ packed: MLXArray) -> MLXArray {
        let (batch, packedChannels, height, width) = dimensions(of: packed)
        let patch = patchSize
        let channels = packedChannels / (patch * patch)
        return
            packed
            .reshaped([batch, channels, patch, patch, height, width])
            .transposed(0, 1, 4, 2, 5, 3)
            .reshaped([batch, channels, height * patch, width * patch])
    }

    /// `[batch, channels, height, width]` to `[batch, height * width, channels]`, row-major.
    public static func tokens(_ grid: MLXArray) -> MLXArray {
        let (batch, channels, height, width) = dimensions(of: grid)
        return grid.reshaped([batch, channels, height * width]).transposed(0, 2, 1)
    }

    /// `[batch, height * width, channels]` back to `[batch, channels, height, width]`.
    public static func grid(_ tokens: MLXArray, height: Int, width: Int) -> MLXArray {
        let batch = tokens.shape[0]
        let channels = tokens.shape[2]
        return tokens.transposed(0, 2, 1).reshaped([batch, channels, height, width])
    }

    /// How many tokens an image of this latent size becomes. The schedule's shift is a function
    /// of this, so it is worth having a name.
    public static func tokenCount(latentHeight: Int, latentWidth: Int) -> Int {
        (latentHeight / patchSize) * (latentWidth / patchSize)
    }

    private static func dimensions(of array: MLXArray) -> (Int, Int, Int, Int) {
        let shape = array.shape
        return (shape[0], shape[1], shape[2], shape[3])
    }
}
