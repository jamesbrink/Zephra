import Foundation
import MLX

/// Root-mean-square normalisation with no learned scale, which is what every norm in the
/// block body is (`norm_elementwise_affine: false`). The queries' and keys' norms do carry a
/// weight and are MLXNN's `RMSNorm` instead.
///
/// Computed in float32 and cast back, as the reference upcasts: a bfloat16 mean of squares over
/// four thousand channels loses digits the modulation then amplifies.
enum LTX2RMSNorm {
    static func normalize(_ x: MLXArray, eps: Float) -> MLXArray {
        let wide = x.asType(.float32)
        let scale = MLX.rsqrt(MLX.mean(wide * wide, axis: -1, keepDims: true) + eps)
        return (wide * scale).asType(x.dtype)
    }
}
