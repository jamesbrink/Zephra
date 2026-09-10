import Foundation
import MLX
import MLXFast
import MLXNN

/// Layer normalisation computed in float32, which is what every norm in the block body and
/// the head is (`FP32LayerNorm`): the reference upcasts the stream, normalises, and casts
/// back, so a bfloat16 mean over three thousand channels never reaches the modulation.
///
/// `norm1`, `norm3` and `norm_out` have no weight and hand back float32, because the
/// modulation that follows them is float32 too and the cast comes after it; `norm2` has a
/// weight and a bias and hands back the stream's dtype, as the cross-attention reads it.
enum WanLayerNorm {
    /// `x` normalised over its last axis, in float32.
    static func normalize(_ x: MLXArray, eps: Float) -> MLXArray {
        MLXFast.layerNorm(x.asType(.float32), weight: nil, bias: nil, eps: eps)
    }

    /// `x` normalised over its last axis and scaled by `norm`'s weight and bias, in `x`'s
    /// dtype.
    static func affine(_ x: MLXArray, by norm: LayerNorm) -> MLXArray {
        MLXFast.layerNorm(
            x.asType(.float32),
            weight: norm.weight?.asType(.float32), bias: norm.bias?.asType(.float32),
            eps: norm.eps
        ).asType(x.dtype)
    }
}
