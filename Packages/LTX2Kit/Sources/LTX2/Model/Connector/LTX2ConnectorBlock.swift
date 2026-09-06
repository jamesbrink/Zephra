import Foundation
import MLX
import MLXNN

/// One block of the connector's 1-D transformer: pre-norm gated attention, pre-norm feed-forward,
/// both residual, both norms without weights.
///
/// The two norms are affine-free RMS norms (`elementwise_affine=False`): the checkpoint carries
/// no `norm1` or `norm2` tensor for a block, and a tree with weighted norms would refuse to load
/// against it.
final class LTX2ConnectorBlock: Module {
    @ModuleInfo(key: "attn1") var attention: LTX2ConnectorAttention
    @ModuleInfo(key: "ff") var feedForward: LTX2ConnectorFeedForward

    private let eps: Float

    init(dim: Int, heads: Int, eps: Float = 1e-6) {
        self.eps = eps
        _attention.wrappedValue = LTX2ConnectorAttention(dim: dim, heads: heads, eps: eps)
        _feedForward.wrappedValue = LTX2ConnectorFeedForward(dim: dim)
    }

    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let attended = x + attention(Self.norm(x, eps: eps), cos: cos, sin: sin)
        return attended + feedForward(Self.norm(attended, eps: eps))
    }

    /// RMS normalisation with no learned scale, in float32 the way the reference computes it.
    static func norm(_ x: MLXArray, eps: Float) -> MLXArray {
        let wide = x.asType(.float32)
        let meanSquare = MLX.mean(wide * wide, axis: -1, keepDims: true)
        return (wide * MLX.rsqrt(meanSquare + eps)).asType(x.dtype)
    }
}
