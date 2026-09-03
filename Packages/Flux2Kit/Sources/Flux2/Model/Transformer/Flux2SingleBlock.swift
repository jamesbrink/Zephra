import Foundation
import MLX
import MLXNN

/// One single-stream block, instantiated twenty times.
///
/// By this point text and image are one sequence, so there is one residual, one norm, and one
/// set of modulation numbers. Attention and the feed-forward run in parallel inside
/// `Flux2ParallelAttention` rather than one after the other, which is why a single gate covers
/// both.
///
/// Like the dual-stream block, the modulation is passed in: all twenty of these share it.
final class Flux2SingleBlock: Module {
    @ModuleInfo(key: "attn") var attention: Flux2ParallelAttention

    private let eps: Float

    init(dim: Int, heads: Int, headDim: Int, mlpHidden: Int, eps: Float) {
        _attention.wrappedValue = Flux2ParallelAttention(
            dim: dim, heads: heads, headDim: headDim, mlpHidden: mlpHidden, eps: eps)
        self.eps = eps
    }

    /// - Parameters:
    ///   - hidden: The joined stream, `[batch, textTokens + imageTokens, dim]`.
    ///   - modulation: The one shared set of shift, scale, and gate.
    ///   - frequencies: The rotary table over that same `[text, image]` sequence.
    func callAsFunction(
        _ hidden: MLXArray,
        modulation: Flux2SharedModulation.Parameters,
        frequencies: RotaryFrequencies
    ) -> MLXArray {
        let normalised = modulation.modulate(Flux2LayerNorm.applied(to: hidden, eps: eps))
        return hidden + modulation.gate * attention(normalised, frequencies: frequencies)
    }
}
