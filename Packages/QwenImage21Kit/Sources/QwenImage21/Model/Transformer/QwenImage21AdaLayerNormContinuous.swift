import Foundation
import MLX
import MLXFast
import MLXNN

/// The final norm, `norm_out`. **Scale only** — this variant emits no shift, so its linear maps
/// to the model's width rather than twice it, and a port that built it the usual way would
/// halve the scale and add a shift made of the other half.
///
/// Its conditioning is `temb`, the timestep embedding itself, **not** the modulation table every
/// block reads. And it selects rows the same way the blocks do, so the prefix is normed from the
/// `t = 0` row here too.
final class QwenImage21AdaLayerNormContinuous: Module {
    @ModuleInfo(key: "linear") var projection: Linear

    private let eps: Float

    init(dim: Int, conditioningDim: Int, eps: Float) {
        _projection.wrappedValue = Linear(conditioningDim, dim, bias: false)
        self.eps = eps
    }

    func callAsFunction(
        _ x: MLXArray, conditioning: MLXArray, targetTokenMask: MLXArray?
    ) -> MLXArray {
        let scale = QwenImage21ModulationRows.select(
            projection(silu(conditioning).asType(x.dtype)), targetTokenMask: targetTokenMask)
        return MLXFast.layerNorm(x, weight: nil, bias: nil, eps: eps) * (1 + scale)
    }
}
