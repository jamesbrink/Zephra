import Foundation
import MLX
import MLXFast
import MLXNN

/// Self-attention in a connector block: gated, with q/k RMS norms across all heads at once.
///
/// Two LTX-2.5 details. The query and key norms span the whole `heads * headDim` width, not
/// one head (`rms_norm_across_heads`), so they sit before the reshape to heads. And each head's
/// output is scaled by a gate, `2 * sigmoid(to_gate_logits(x))`, read from the block's *input*
/// before any projection; the factor of two makes a zero-initialised gate the identity.
final class LTX2ConnectorAttention: Module {
    @ModuleInfo(key: "to_q") var toQueries: Linear
    @ModuleInfo(key: "to_k") var toKeys: Linear
    @ModuleInfo(key: "to_v") var toValues: Linear
    @ModuleInfo(key: "to_out") var toOut: Linear
    @ModuleInfo(key: "q_norm") var queryNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: RMSNorm
    @ModuleInfo(key: "to_gate_logits") var toGateLogits: Linear

    private let heads: Int
    private let headDim: Int

    init(dim: Int, heads: Int, eps: Float = 1e-6) {
        self.heads = heads
        headDim = dim / heads
        _toQueries.wrappedValue = Linear(dim, dim, bias: true)
        _toKeys.wrappedValue = Linear(dim, dim, bias: true)
        _toValues.wrappedValue = Linear(dim, dim, bias: true)
        // The checkpoint numbers this `to_out.0`, after a dropout; `LTX2ConnectorWeights` drops
        // the number on the way in, since a numbered child cannot be both loaded and packed.
        _toOut.wrappedValue = Linear(dim, dim, bias: true)
        _queryNorm.wrappedValue = RMSNorm(dimensions: dim, eps: eps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: dim, eps: eps)
        _toGateLogits.wrappedValue = Linear(dim, heads, bias: true)
    }

    /// Attends over `x`, `[batch, length, dim]`, rotating queries and keys by the tables.
    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let (batch, length) = (x.dim(0), x.dim(1))
        let gates = 2 * MLX.sigmoid(toGateLogits(x))
        let queries = LTX2ConnectorRotaryEmbedding.rotate(
            queryNorm(toQueries(x)).reshaped(batch, length, heads, headDim), cos: cos, sin: sin)
        let keys = LTX2ConnectorRotaryEmbedding.rotate(
            keyNorm(toKeys(x)).reshaped(batch, length, heads, headDim), cos: cos, sin: sin)
        let values = toValues(x).reshaped(batch, length, heads, headDim)
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries.transposed(0, 2, 1, 3),
            keys: keys.transposed(0, 2, 1, 3),
            values: values.transposed(0, 2, 1, 3),
            scale: 1 / Float(headDim).squareRoot(),
            mask: nil
        ).transposed(0, 2, 1, 3)
        let gated = attended * gates.asType(attended.dtype)[0..., 0..., 0..., .newAxis]
        return toOut(gated.reshaped(batch, length, heads * headDim))
    }
}
