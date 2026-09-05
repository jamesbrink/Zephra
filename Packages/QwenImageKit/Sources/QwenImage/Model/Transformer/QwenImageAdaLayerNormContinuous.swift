import Foundation
import MLX
import MLXFast
import MLXNN

/// The final norm, conditioned on the timestep.
///
/// It chunks **scale first, then shift** — the opposite order from the modulation inside a
/// block. Both produce a tensor of the right shape either way round, and swapping them changes
/// the image without breaking anything, so the two are kept apart deliberately.
///
/// The layer norm itself has no learnable parameters, which is why the checkpoint carries only
/// `norm_out.linear`.
final class QwenImageAdaLayerNormContinuous: Module {
    @ModuleInfo(key: "linear") var projection: Linear

    private let eps: Float

    init(dim: Int, eps: Float = 1e-6) {
        _projection.wrappedValue = Linear(dim, dim * 2, bias: true)
        self.eps = eps
    }

    func callAsFunction(_ x: MLXArray, conditioning: MLXArray) -> MLXArray {
        let parameters = projection(silu(conditioning))
        let width = parameters.shape[parameters.ndim - 1] / 2
        let scale = parameters[.ellipsis, ..<width].expandedDimensions(axis: 1)
        let shift = parameters[.ellipsis, width...].expandedDimensions(axis: 1)
        return MLXFast.layerNorm(x, weight: nil, bias: nil, eps: eps) * (1 + scale) + shift
    }
}
