import Foundation
import MLX
import MLXNN

/// The six numbers per stream, per block, that the conditioning vector turns into.
///
/// One projection produces six chunks: a shift, a scale, and a gate for the attention half of
/// the block, and the same three for the feed-forward half. At `6 * 3072` wide across 60 blocks
/// and two streams this single layer is a third of the model's parameters, which is why it is
/// the one worth keeping at eight bits when everything else goes to four.
///
/// The reference builds it as `Sequential(SiLU, Linear)`, so the checkpoint calls the
/// projection `1`. That position is renamed on the way in; the SiLU is applied here.
///
/// The chunk order is `shift, scale, gate`, and modulation is `x * (1 + scale) + shift`. The
/// final norm chunks the other way round; see `QwenImageAdaLayerNormContinuous`.
final class QwenImageStreamModulation: Module {
    /// Shift, scale, and gate for one half of a block.
    struct Parameters {
        let shift: MLXArray
        let scale: MLXArray
        let gate: MLXArray

        /// Applies the shift and scale, leaving the gate for the residual.
        func modulate(_ x: MLXArray) -> MLXArray {
            x * (1 + scale) + shift
        }
    }

    @ModuleInfo(key: "projection") var projection: Linear

    init(dim: Int) {
        _projection.wrappedValue = Linear(dim, 6 * dim, bias: true)
    }

    /// The attention half's parameters and the feed-forward half's, in that order.
    func callAsFunction(_ conditioning: MLXArray)
        -> (attention: Parameters, feedForward: Parameters)
    {
        let all = projection(silu(conditioning))
        let width = all.shape[all.ndim - 1] / 6
        func chunk(_ index: Int) -> MLXArray {
            all[.ellipsis, (index * width)..<((index + 1) * width)].expandedDimensions(axis: 1)
        }
        return (
            Parameters(shift: chunk(0), scale: chunk(1), gate: chunk(2)),
            Parameters(shift: chunk(3), scale: chunk(4), gate: chunk(5))
        )
    }
}
