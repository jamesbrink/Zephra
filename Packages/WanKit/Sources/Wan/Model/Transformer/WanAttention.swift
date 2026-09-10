import Foundation
import MLX
import MLXFast
import MLXNN

/// Attention as every Wan block has it, twice: over the clip's own tokens with the rotary
/// embedding, and over the text without it.
///
/// Queries and keys are RMS-normalised across the whole `heads * headDim` width, with a
/// learned weight, before the heads are split (`rms_norm_across_heads`); normalising per head
/// instead is the mistake most worth naming. Every projection carries a bias. The output
/// projection is `to_out.0` in the checkpoint, a one-element list; `WanTransformerWeights`
/// folds the index away.
final class WanAttention: Module {
    @ModuleInfo(key: "to_q") var query: Linear
    @ModuleInfo(key: "to_k") var key: Linear
    @ModuleInfo(key: "to_v") var value: Linear
    @ModuleInfo(key: "to_out") var output: Linear
    @ModuleInfo(key: "norm_q") var queryNorm: RMSNorm
    @ModuleInfo(key: "norm_k") var keyNorm: RMSNorm

    private let heads: Int
    private let headDim: Int
    private let scale: Float

    init(dim: Int, heads: Int, headDim: Int, eps: Float) {
        self.heads = heads
        self.headDim = headDim
        scale = 1 / sqrt(Float(headDim))
        let inner = heads * headDim
        _query.wrappedValue = Linear(dim, inner, bias: true)
        _key.wrappedValue = Linear(dim, inner, bias: true)
        _value.wrappedValue = Linear(dim, inner, bias: true)
        _output.wrappedValue = Linear(inner, dim, bias: true)
        _queryNorm.wrappedValue = RMSNorm(dimensions: inner, eps: eps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: inner, eps: eps)
    }

    /// - Parameters:
    ///   - x: `[batch, tokens, dim]`, already normalised and modulated by the caller.
    ///   - context: What to attend over, `[batch, contextTokens, dim]`, or nil for `x`.
    ///   - rotary: The clip's table, rotating queries and keys, or nil for none.
    func callAsFunction(
        _ x: MLXArray, context: MLXArray? = nil, rotary: WanRotaryTable? = nil
    ) -> MLXArray {
        let batch = x.shape[0]
        let source = context ?? x
        var queries = split(queryNorm(query(x)))
        var keys = split(keyNorm(key(source)))
        if let rotary {
            queries = rotary.rotate(queries)
            keys = rotary.rotate(keys)
        }
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries.transposed(0, 2, 1, 3),
            keys: keys.transposed(0, 2, 1, 3),
            values: split(value(source)).transposed(0, 2, 1, 3),
            scale: scale,
            mask: nil
        )
        // [batch, heads, tokens, headDim] -> [batch, tokens, heads * headDim]
        return output(attended.transposed(0, 2, 1, 3).reshaped([batch, -1, heads * headDim]))
    }

    /// `[batch, tokens, heads * headDim]` into `[batch, tokens, heads, headDim]`, the layout
    /// the rotary table rotates.
    private func split(_ x: MLXArray) -> MLXArray {
        x.reshaped([x.shape[0], x.shape[1], heads, headDim])
    }
}
