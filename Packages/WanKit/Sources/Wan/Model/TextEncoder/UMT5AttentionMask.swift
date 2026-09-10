import Foundation
import MLX

/// The additive mask a right-padded prompt needs: every key that is padding is hidden from
/// every query, and nothing else is.
///
/// The encoder is bidirectional, so there is no causal half; and because a padded query still
/// sees every real key, no row of the mask is entirely blocked and no softmax can reach NaN.
/// The mask is built once per forward pass and shared by every layer, which adds its own
/// position bias to it; a large finite negative rather than the dtype's minimum, so that the
/// bias added on top cannot push a logit to infinity.
enum UMT5AttentionMask {
    /// `[batch, 1, 1, length]`, from a `[batch, length]` mask of ones over the real tokens,
    /// in the dtype the scores are computed in.
    static func additive(padding: MLXArray, dtype: DType) -> MLXArray {
        MLX.where(padding .== 0, MLXArray(Float(-1e9)), MLXArray(Float(0)))
            .asType(dtype)[0..., .newAxis, .newAxis, 0...]
    }
}
