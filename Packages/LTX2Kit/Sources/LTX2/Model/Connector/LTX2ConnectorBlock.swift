import Foundation
import MLX
import MLXNN

/// One block of the connector's 1-D transformer: pre-norm gated self-attention, pre-norm
/// feed-forward, both residual, both norms without weights.
///
/// The attention and the feed-forward are the DiT's own modules: the same seven attention
/// tensors with the same per-head gate, and the same tanh-GELU expansion, here with biases.
/// The two norms are affine-free RMS norms (`elementwise_affine=False`): the checkpoint carries
/// no `norm1` or `norm2` tensor for a block, and a tree with weighted norms would refuse to load
/// against it.
final class LTX2ConnectorBlock: Module {
    @ModuleInfo(key: "attn1") var attention: LTX2GatedAttention
    @ModuleInfo(key: "ff") var feedForward: LTX2FeedForward

    private let eps: Float

    init(dim: Int, heads: Int, eps: Float = 1e-6) {
        self.eps = eps
        _attention.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: dim, heads: heads, headDim: dim / heads, eps: eps)
        _feedForward.wrappedValue = LTX2FeedForward(dim: dim, hidden: dim * 4, bias: true)
    }

    func callAsFunction(_ x: MLXArray, rotary: LTX2RotaryTable) -> MLXArray {
        let attended = x + attention(LTX2RMSNorm.normalize(x, eps: eps), rotary: rotary)
        return attended + feedForward(LTX2RMSNorm.normalize(attended, eps: eps))
    }
}
