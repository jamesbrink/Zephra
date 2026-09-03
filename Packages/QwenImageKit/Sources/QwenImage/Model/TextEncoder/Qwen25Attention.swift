import Foundation
import MLX
import MLXFast
import MLXNN

/// Grouped-query self-attention, Qwen2.5 style.
///
/// Two details separate this from the Qwen3 encoder Z-Image uses, and getting either backwards
/// ports the wrong model while compiling perfectly: **the query, key, and value projections
/// carry a bias** here, and there is **no per-head query or key norm**. Qwen3 is the exact
/// opposite on both counts.
///
/// Rotation here is the half-split convention (`traditional: false`), which is what the
/// reference language model uses. The image transformer rotates adjacent pairs instead. The two
/// live in the same package and are not interchangeable.
final class Qwen25Attention: Module {
    @ModuleInfo(key: "q_proj") var queryProjection: Linear
    @ModuleInfo(key: "k_proj") var keyProjection: Linear
    @ModuleInfo(key: "v_proj") var valueProjection: Linear
    @ModuleInfo(key: "o_proj") var outputProjection: Linear
    @ModuleInfo(key: "rope") var rope: RoPE

    private let heads: Int
    private let keyValueHeads: Int
    private let headDim: Int
    private let scale: Float

    init(_ configuration: QwenImageTextEncoderConfiguration) {
        heads = configuration.numAttentionHeads
        keyValueHeads = configuration.numKeyValueHeads
        headDim = configuration.headDim
        scale = 1 / sqrt(Float(headDim))

        let hidden = configuration.hiddenSize
        _queryProjection.wrappedValue = Linear(hidden, heads * headDim, bias: true)
        _keyProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: true)
        _valueProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: true)
        _outputProjection.wrappedValue = Linear(heads * headDim, hidden, bias: false)
        _rope.wrappedValue = RoPE(
            dimensions: headDim, traditional: false, base: configuration.ropeTheta)
    }

    /// Attends over `x`, `[batch, tokens, hidden]`, with an additive `mask`.
    func callAsFunction(_ x: MLXArray, mask: MLXArray?) -> MLXArray {
        let (batch, tokens) = (x.shape[0], x.shape[1])

        var queries = queryProjection(x)
            .reshaped(batch, tokens, heads, headDim).transposed(0, 2, 1, 3)
        var keys = keyProjection(x)
            .reshaped(batch, tokens, keyValueHeads, headDim).transposed(0, 2, 1, 3)
        let values = valueProjection(x)
            .reshaped(batch, tokens, keyValueHeads, headDim).transposed(0, 2, 1, 3)

        queries = rope(queries)
        keys = rope(keys)

        // MLX's attention broadcasts the key-value heads across their query group itself.
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, tokens, heads * headDim)

        return outputProjection(attended)
    }
}
