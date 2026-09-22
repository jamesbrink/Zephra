import Foundation
import MLX
import MLXFast
import MLXNN

/// Grouped-query self-attention in a Qwen3-VL decoder layer: 32 query heads to 8 key-value
/// heads, each head's queries and keys RMS normed, and no bias anywhere.
///
/// `attention_bias` is false and the checkpoint carries no bias tensor for any of the four
/// projections, which `WeightKeyCoverageTests` pins. The head width is **stated** by the
/// config — 128 against a model 4096 wide over 32 heads, which happens to agree here, but
/// deriving it would be the wrong rule and is what breaks on the doll's house.
///
/// The order is load-bearing: project, split each head onto its own row, norm that row, move
/// the heads in front, then rotate. Norming after the transpose gives the same answer; norming
/// before the split does not, because it would span every head at once.
final class Qwen3VLAttention: Module {
    @ModuleInfo(key: "q_proj") var queryProjection: Linear
    @ModuleInfo(key: "k_proj") var keyProjection: Linear
    @ModuleInfo(key: "v_proj") var valueProjection: Linear
    @ModuleInfo(key: "o_proj") var outputProjection: Linear
    @ModuleInfo(key: "q_norm") var queryNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: RMSNorm

    private let heads: Int
    private let keyValueHeads: Int
    private let headDim: Int
    private let scale: Float

    init(_ configuration: Qwen3VLTextConfiguration.Text) {
        heads = configuration.numAttentionHeads
        keyValueHeads = configuration.numKeyValueHeads
        headDim = configuration.headDim
        scale = 1 / sqrt(Float(headDim))

        let hidden = configuration.hiddenSize
        _queryProjection.wrappedValue = Linear(hidden, heads * headDim, bias: false)
        _keyProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: false)
        _valueProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: false)
        _outputProjection.wrappedValue = Linear(heads * headDim, hidden, bias: false)

        // Over one head's width, never the model's. This is what says Qwen3 rather than
        // Qwen2.5, which biases the projections above and norms nothing per head.
        _queryNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: configuration.rmsNormEps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: configuration.rmsNormEps)
    }

    /// Attends over `x`, `[batch, tokens, hidden]`, rotated by `cos` and `sin` and masked.
    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray, mask: MLXArray?) -> MLXArray
    {
        let (batch, tokens) = (x.dim(0), x.dim(1))

        var queries = queryNorm(
            queryProjection(x).reshaped(batch, tokens, heads, headDim)
        ).transposed(0, 2, 1, 3)
        var keys = keyNorm(
            keyProjection(x).reshaped(batch, tokens, keyValueHeads, headDim)
        ).transposed(0, 2, 1, 3)
        let values = valueProjection(x)
            .reshaped(batch, tokens, keyValueHeads, headDim).transposed(0, 2, 1, 3)

        queries = Qwen3VLRotary.applied(queries, cos: cos, sin: sin)
        keys = Qwen3VLRotary.applied(keys, cos: cos, sin: sin)

        // MLX's attention broadcasts the key-value heads across their query group itself.
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, tokens, heads * headDim)

        return outputProjection(attended)
    }
}
