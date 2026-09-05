import Foundation
import MLX
import MLXFast
import MLXNN

/// The final norm, conditioned on the timestep.
///
/// It chunks **scale first, then shift** — the opposite order from `Flux2SharedModulation`,
/// which every block uses. Both orders produce tensors of the right shape, and swapping them
/// changes the image without breaking anything, so the two are kept apart deliberately.
///
/// The layer norm itself has nothing learned, which is why the checkpoint carries only
/// `norm_out.linear`. The linear is bias-free like the rest of the model.
final class Flux2AdaLayerNormContinuous: Module {
    @ModuleInfo(key: "linear") var projection: Linear

    private let eps: Float

    init(dim: Int, eps: Float) {
        _projection.wrappedValue = Linear(dim, dim * 2, bias: false)
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
