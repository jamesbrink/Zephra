import Foundation
import MLX
import MLXFast
import MLXNN

/// Attention with a learned gate per head, as every attention module in LTX-2.5 is.
///
/// Queries and keys are RMS-normalised across the whole `heads * headDim` width, with a
/// learned weight, before the rotary embedding is applied and before the heads are split; the
/// reference calls this `rms_norm_across_heads`, and normalising per head instead is the
/// mistake most worth naming. The gate is `2 * sigmoid(to_gate_logits(x))`, one value per head
/// computed from the attention's own input, multiplied into the attended heads before the
/// output projection; the factor of two makes a zero-initialised gate the identity.
///
/// Self-attention passes no `context` and a rotary table; cross-attention to the text passes
/// the text as `context` and no table. Every projection carries a bias.
final class LTX2GatedAttention: Module {
    @ModuleInfo(key: "to_q") var query: Linear
    @ModuleInfo(key: "to_k") var key: Linear
    @ModuleInfo(key: "to_v") var value: Linear
    @ModuleInfo(key: "to_out") var output: Linear
    @ModuleInfo(key: "q_norm") var queryNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: RMSNorm
    @ModuleInfo(key: "to_gate_logits") var gateLogits: Linear

    private let heads: Int
    private let headDim: Int
    private let scale: Float

    /// - Parameters:
    ///   - queryDim: Width of the stream the queries come from, and of the output.
    ///   - contextDim: Width of what the keys and values are made from; `queryDim` for
    ///     self-attention.
    init(queryDim: Int, contextDim: Int, heads: Int, headDim: Int, eps: Float) {
        self.heads = heads
        self.headDim = headDim
        scale = 1 / sqrt(Float(headDim))
        let inner = heads * headDim
        _query.wrappedValue = Linear(queryDim, inner, bias: true)
        _key.wrappedValue = Linear(contextDim, inner, bias: true)
        _value.wrappedValue = Linear(contextDim, inner, bias: true)
        _output.wrappedValue = Linear(inner, queryDim, bias: true)
        _queryNorm.wrappedValue = RMSNorm(dimensions: inner, eps: eps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: inner, eps: eps)
        _gateLogits.wrappedValue = Linear(queryDim, heads, bias: true)
    }

    /// - Parameters:
    ///   - x: `[batch, tokens, queryDim]`, already normalised and modulated by the caller.
    ///   - context: What to attend over, `[batch, contextTokens, contextDim]`, or nil for `x`.
    ///   - rotary: The table to rotate queries and keys with, or nil for none.
    ///   - mask: An additive bias broadcastable to `[batch, heads, tokens, contextTokens]`.
    func callAsFunction(
        _ x: MLXArray, context: MLXArray? = nil, rotary: LTX2RotaryTable? = nil, mask: MLXArray? = nil
    ) -> MLXArray {
        let batch = x.shape[0]
        let source = context ?? x
        let gates = 2 * sigmoid(gateLogits(x))
        let queries = queryNorm(query(x))
        let keys = keyNorm(key(source))
        let attended = MLXFast.scaledDotProductAttention(
            queries: rotary?.rotate(queries) ?? split(queries),
            keys: rotary?.rotate(keys) ?? split(keys),
            values: split(value(source)),
            scale: scale,
            mask: mask
        )
        // [batch, heads, tokens, headDim] -> [batch, tokens, heads, headDim], gated per head.
        let gated = attended.transposed(0, 2, 1, 3) * gates.expandedDimensions(axis: -1)
        return output(gated.reshaped([batch, -1, heads * headDim]))
    }

    /// `[batch, tokens, heads * headDim]` into heads-major `[batch, heads, tokens, headDim]`.
    private func split(_ x: MLXArray) -> MLXArray {
        x.reshaped([x.shape[0], x.shape[1], heads, headDim]).transposed(0, 2, 1, 3)
    }
}
