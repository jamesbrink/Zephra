import Foundation
import MLX
import MLXNN

/// RMS norm whose learnable weight is stored **zero-centred**: the effective scale is
/// `weight + 1`.
///
/// The `+ 1` is load-bearing. The checkpoint stores `scale - 1`, so a plain `RMSNorm` over these
/// weights multiplies the text stream by something near zero and annihilates it — a model that
/// loads cleanly and makes a picture of nothing in particular. Used by `txt_in.text_norm` and
/// nowhere else; the per-head query and key norms are ordinary `RMSNorm`s.
///
/// The statistic and the scale are computed in float32 whatever the stream is, which is what
/// the reference does, and the result comes back in the input's own dtype.
final class QwenImage21ZeroCenterRMSNorm: Module {
    let weight: MLXArray

    private let eps: Float

    init(dimensions: Int, eps: Float) {
        weight = MLXArray.zeros([dimensions])
        self.eps = eps
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let wide = x.asType(.float32)
        let inverse = MLX.rsqrt(MLX.mean(wide * wide, axis: -1, keepDims: true) + eps)
        return (wide * inverse * (weight.asType(.float32) + 1)).asType(x.dtype)
    }
}
