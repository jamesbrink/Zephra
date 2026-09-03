import Foundation
import MLX

/// Trading channels for pixels: `[N, H, W, C * r * r]` becomes `[N, H * r, W * r, C]`.
///
/// MLX has no pixel shuffle, so this is hand-rolled, and the ordering is the whole of it.
/// PyTorch's `PixelShuffle(r)` reads its input channel axis as `(C, r_row, r_col)` — channel
/// major, then the row within the block, then the column — and our last axis is that same axis
/// unpermuted, because a PyTorch `[N, C, H, W]` and an MLX `[N, H, W, C]` differ only in where
/// the channel axis sits, not in how it is laid out.
///
/// So the three plausible wrong orderings — `(r, r, C)`, `(r, C, r)`, and transposing the block
/// axes ahead of the spatial ones — all produce a picture of the right size out of the wrong
/// pixels, which is why `PixelShuffleTests` pins it against a torch fixture whose values are an
/// `arange` and so name their own coordinates.
public enum PixelShuffle {
    /// Shuffles `x`, `[N, H, W, C * factor * factor]` in NHWC, into `[N, H * factor, W * factor, C]`.
    public static func apply(_ x: MLXArray, factor: Int) -> MLXArray {
        let (batch, height, width) = (x.dim(0), x.dim(1), x.dim(2))
        let channels = x.dim(3) / (factor * factor)
        return
            x
            .reshaped([batch, height, width, channels, factor, factor])
            .transposed(0, 1, 4, 2, 5, 3)
            .reshaped([batch, height * factor, width * factor, channels])
    }
}
