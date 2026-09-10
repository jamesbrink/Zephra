import Foundation
import MLX
import MLXFast
import MLXNN

/// One UMT5 self-attention layer with its own relative position bias table.
///
/// Two things here are T5's own and easy to lose to habit. **Scores are not scaled**: the
/// reference sets the scale to 1 and lets the projections carry it, so a 1 / sqrt(d) here
/// would quietly cool every attention map. And **every layer owns a bias table**, which is
/// what makes UMT5 not T5: in T5 only the first layer has one and the rest reuse its output,
/// whereas the checkpoint here carries `relative_attention_bias` in all 24 blocks. The table
/// is `[buckets, heads]`, gathered by the bucket of each query-key distance and added to the
/// logits along with the padding mask.
final class UMT5Attention: Module {
    @ModuleInfo(key: "q") var query: Linear
    @ModuleInfo(key: "k") var key: Linear
    @ModuleInfo(key: "v") var value: Linear
    @ModuleInfo(key: "o") var output: Linear
    @ModuleInfo(key: "relative_attention_bias") var relativeAttentionBias: Embedding

    private let heads: Int
    private let headDim: Int

    init(_ configuration: UMT5Configuration) {
        heads = configuration.numHeads
        headDim = configuration.dKV
        let inner = heads * headDim
        _query.wrappedValue = Linear(configuration.dModel, inner, bias: false)
        _key.wrappedValue = Linear(configuration.dModel, inner, bias: false)
        _value.wrappedValue = Linear(configuration.dModel, inner, bias: false)
        _output.wrappedValue = Linear(inner, configuration.dModel, bias: false)
        _relativeAttentionBias.wrappedValue = Embedding(
            embeddingCount: configuration.relativeAttentionNumBuckets, dimensions: heads)
    }

    /// This layer's bias for every query and key, `[1, heads, length, length]`, from the
    /// `[length, length]` table of buckets `UMT5RelativePositionBucket` builds once per pass.
    func positionBias(buckets: MLXArray) -> MLXArray {
        relativeAttentionBias(buckets).transposed(2, 0, 1)[.newAxis]
    }

    /// Attends over `x`, `[batch, length, hidden]`, under the additive padding `mask`,
    /// `[batch, 1, 1, length]`, and this layer's bias for `buckets`.
    func callAsFunction(_ x: MLXArray, mask: MLXArray, buckets: MLXArray) -> MLXArray {
        let (batch, length) = (x.dim(0), x.dim(1))
        let queries = query(x).reshaped(batch, length, heads, headDim).transposed(0, 2, 1, 3)
        let keys = key(x).reshaped(batch, length, heads, headDim).transposed(0, 2, 1, 3)
        let values = value(x).reshaped(batch, length, heads, headDim).transposed(0, 2, 1, 3)
        let bias = (positionBias(buckets: buckets) + mask).asType(queries.dtype)
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: 1, mask: bias
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, length, heads * headDim)
        return output(attended)
    }
}
