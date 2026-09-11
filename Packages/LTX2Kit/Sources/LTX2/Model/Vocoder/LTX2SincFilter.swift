import Foundation
import MLX

/// A one-channel filter run over every channel of a signal: what the vocoder's anti-aliasing
/// and resampling do with `groups = channels`, which mlx-swift's convolutions do not take.
///
/// The signal `[batch, samples, channels]` is folded to `[batch * channels, samples, 1]`, the
/// filter `[1, taps, 1]` applied once, and the result unfolded; exact, since every channel
/// sees the same taps. Padding is by edge, the reference's `replicate`.
enum LTX2SincFilter {
    /// `x` filtered with stride `stride`, padded by `before` and `after` samples first.
    static func convolved(_ x: MLXArray, filter: MLXArray, stride: Int, before: Int, after: Int) -> MLXArray {
        let folded = fold(x)
        let padded = MLX.padded(folded, widths: [0, [before, after], 0], mode: .edge)
        return unfold(MLX.conv1d(padded, filter.asType(x.dtype), stride: stride), batch: x.dim(0))
    }

    /// `x` upsampled `ratio` times through the transposed filter, padded by `pad` first and
    /// trimmed by `before` and `after` after, scaled by `ratio`.
    static func transposed(
        _ x: MLXArray, filter: MLXArray, ratio: Int, pad: Int, before: Int, after: Int
    ) -> MLXArray {
        let folded = MLX.padded(fold(x), widths: [0, [pad, pad], 0], mode: .edge)
        let wide = MLX.convTransposed1d(folded, filter.asType(x.dtype), stride: ratio) * Float(ratio)
        let trimmed = wide[0..., before..<(wide.dim(1) - after), 0...]
        return unfold(trimmed, batch: x.dim(0))
    }

    /// `[batch, samples, channels]` to `[batch * channels, samples, 1]`.
    private static func fold(_ x: MLXArray) -> MLXArray {
        x.transposed(0, 2, 1).reshaped([x.dim(0) * x.dim(2), x.dim(1), 1])
    }

    /// The fold undone, for `batch` items.
    private static func unfold(_ x: MLXArray, batch: Int) -> MLXArray {
        x.reshaped([batch, -1, x.dim(1)]).transposed(0, 2, 1)
    }
}
