import Foundation
import MLX
import MLXNN

/// The one modulation table every block reads, `modulation`.
///
/// This is the biggest structural difference from Qwen-Image 2512, and a port that misses it
/// loads a checkpoint with 32 tables missing and modulates by whatever the initialiser left
/// behind. 2.1 has **one** `Linear(SiLU(temb))` for the whole model, producing four vectors — a
/// scale and a gate for the attention half, a scale and a gate for the feed-forward half — and
/// all 32 blocks read the same four.
///
/// The checkpoint names the linear `modulation.1`, its position in a `Sequential` whose first
/// element is the activation. `QwenImage21TransformerWeights` renames that to `projection`,
/// since a numbered child is a tree MLX can load or quantize but not both.
final class QwenImage21SharedModulation: Module {
    /// The four vectors, already selected per token. Each is `[batch, 1, dim]` or
    /// `[batch, tokens, dim]`, depending on whether a target mask was in play.
    struct Parameters {
        /// Scale for the attention half.
        let attentionScale: MLXArray
        /// Gate for the attention half. **`tanh` of this** gates the residual, never the raw
        /// value.
        let attentionGate: MLXArray
        /// Scale for the feed-forward half.
        let mlpScale: MLXArray
        /// Gate for the feed-forward half, also through `tanh`.
        let mlpGate: MLXArray
    }

    @ModuleInfo(key: "projection") var projection: Linear

    init(dim: Int) {
        _projection.wrappedValue = Linear(dim, 4 * dim, bias: false)
    }

    /// The raw table, `[rows, 4 * dim]`, for a conditioning of `[rows, dim]`.
    func callAsFunction(_ conditioning: MLXArray) -> MLXArray {
        projection(silu(conditioning))
    }

    /// Chunks the table into its four vectors and selects each one's rows.
    ///
    /// The reference chunks twice — the table into `mod1, mod2`, then each of those into a
    /// scale and a gate — which puts the four in the order below. Getting the order wrong
    /// gates by a scale and scales by a gate, and the picture is merely strange.
    static func split(_ table: MLXArray, targetTokenMask: MLXArray?) -> Parameters {
        let width = table.dim(-1) / 4
        func chunk(_ index: Int) -> MLXArray {
            QwenImage21ModulationRows.select(
                table[.ellipsis, (index * width)..<((index + 1) * width)],
                targetTokenMask: targetTokenMask)
        }
        return Parameters(
            attentionScale: chunk(0), attentionGate: chunk(1),
            mlpScale: chunk(2), mlpGate: chunk(3))
    }
}
