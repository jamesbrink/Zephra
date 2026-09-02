import Foundation
import MLX

/// Layer normalisation with nothing learned.
///
/// The transformer's norms have `elementwise_affine=False`: every scale and shift comes from the
/// timestep conditioning instead, which is what the modulation is for. So this is a function
/// rather than a module — a parameterless `Module` would sit in the tree with nothing in it,
/// and MLX cannot walk past an unwrapped one when it replaces layers for quantization.
enum QwenImageLayerNorm {
    /// Normalises the last axis of `x` to zero mean and unit variance.
    static func applied(to x: MLXArray, eps: Float = 1e-6) -> MLXArray {
        let mean = MLX.mean(x, axis: -1, keepDims: true)
        let centred = x - mean
        let variance = MLX.mean(centred * centred, axis: -1, keepDims: true)
        return centred * MLX.rsqrt(variance + eps)
    }
}
