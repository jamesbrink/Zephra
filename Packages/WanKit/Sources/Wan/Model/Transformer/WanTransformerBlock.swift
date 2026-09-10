import Foundation
import MLX
import MLXNN

/// One of the thirty blocks: self-attention over the clip, cross-attention to the text, and a
/// feed-forward, the first and last behind an adaptive norm with its own shift, scale and
/// gate.
///
/// The modulation is **per token**: `e = scale_shift_table + timestep_proj`, where the
/// timestep is a field over the tokens rather than one number, because an image-to-video run
/// tells the first frame's tokens they are at timestep 0 while the rest are at the step's.
/// The table ships in the checkpoint's dtype and the sum is taken in float32, as the
/// reference takes it, so a table left wide by a loader cannot widen every activation after
/// it. The cross-attention has no modulation and no gate; `norm2` before it carries a weight
/// and a bias (`cross_attn_norm`).
final class WanTransformerBlock: Module {
    @ModuleInfo(key: "attn1") var selfAttention: WanAttention
    @ModuleInfo(key: "attn2") var crossAttention: WanAttention
    @ModuleInfo(key: "norm2") var crossNorm: LayerNorm
    @ModuleInfo(key: "ffn") var feedForward: WanFeedForward
    @ParameterInfo(key: "scale_shift_table") var table: MLXArray

    private let eps: Float

    init(_ configuration: WanTransformerConfiguration) {
        let dim = configuration.innerDim
        eps = configuration.eps
        _selfAttention.wrappedValue = WanAttention(
            dim: dim, heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim, eps: eps)
        _crossAttention.wrappedValue = WanAttention(
            dim: dim, heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim, eps: eps)
        _crossNorm.wrappedValue = LayerNorm(dimensions: dim, eps: eps, affine: true)
        _feedForward.wrappedValue = WanFeedForward(dim: dim, hidden: configuration.ffnDim)
        _table.wrappedValue = MLXArray.zeros([1, WanTransformerConfiguration.blockModulationRows, dim])
    }

    /// - Parameters:
    ///   - hidden: The stream, `[batch, tokens, dim]`.
    ///   - text: The projected text, `[batch, textTokens, dim]`, in the stream's dtype.
    ///   - modulation: The timestep's six rows per token, `[batch, tokens, 6, dim]`, or
    ///     `[batch, 1, 6, dim]` when every token is at the same timestep.
    ///   - rotary: The clip's rotary table, for the self-attention.
    func callAsFunction(
        _ hidden: MLXArray, text: MLXArray, modulation: MLXArray, rotary: WanRotaryTable
    ) -> MLXArray {
        let rows = Self.rows(table, modulation)
        var x = hidden

        var normed = (WanLayerNorm.normalize(x, eps: eps) * (1 + rows[1]) + rows[0]).asType(x.dtype)
        x = (x.asType(.float32) + selfAttention(normed, rotary: rotary) * rows[2]).asType(x.dtype)

        normed = WanLayerNorm.affine(x, by: crossNorm)
        x = x + crossAttention(normed, context: text)

        normed = (WanLayerNorm.normalize(x, eps: eps) * (1 + rows[4]) + rows[3]).asType(x.dtype)
        return (x.asType(.float32) + feedForward(normed).asType(.float32) * rows[5]).asType(x.dtype)
    }

    /// A `[1, rows, dim]` table added to a `[batch, tokens, rows, dim]` modulation in float32,
    /// split into one `[batch, tokens, dim]` per row: shift, scale and gate for the
    /// self-attention, then for the feed-forward.
    static func rows(_ table: MLXArray, _ modulation: MLXArray) -> [MLXArray] {
        let summed = table.asType(.float32).expandedDimensions(axis: 0) + modulation.asType(.float32)
        return (0..<table.shape[1]).map { summed[0..., 0..., $0, 0...] }
    }
}
