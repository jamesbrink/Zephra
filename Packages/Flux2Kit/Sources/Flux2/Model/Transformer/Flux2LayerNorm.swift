import Foundation
import MLX

/// Layer normalisation with nothing learned.
///
/// Every norm inside the transformer has `elementwise_affine=False`: the scale and the shift
/// arrive from the timestep conditioning instead, which is what the modulation is for. So this
/// is a function rather than a module — a parameterless `Module` would sit in the tree holding
/// nothing, and MLX cannot walk past an unwrapped one when it replaces layers for quantization.
///
/// The epsilon is the config's `eps`, 1e-6. Two of the three Swift ports of this model use
/// 1e-5 here and in the query and key norms, which is a difference no test catches and no
/// output obviously shows.
enum Flux2LayerNorm {
    /// Normalises the last axis of `x` to zero mean and unit variance.
    static func applied(to x: MLXArray, eps: Float = 1e-6) -> MLXArray {
        let mean = MLX.mean(x, axis: -1, keepDims: true)
        let centred = x - mean
        let variance = MLX.mean(centred * centred, axis: -1, keepDims: true)
        return centred * MLX.rsqrt(variance + eps)
    }
}
