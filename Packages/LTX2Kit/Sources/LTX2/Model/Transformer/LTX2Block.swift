import Foundation
import MLX
import MLXNN

/// One of the forty-eight video blocks: self-attention over the clip, cross-attention to the
/// text, and a feed-forward, each behind an adaptive norm with its own shift, scale and gate.
///
/// The modulation is the timestep's rows plus this block's own `scale_shift_table`, nine rows
/// wide because the cross-attention's queries are modulated too (`cross_attention_adaln`), and
/// the text the cross-attention reads is shifted and scaled by `prompt_scale_shift_table` plus
/// the prompt rows. Both tables ship in float32 and are cast to the stream here, so a table
/// left wide by a loader cannot widen every activation after it.
///
/// **The audio seam.** The full model runs an audio lane beside this one, joined by a gated
/// cross-attention in both directions between the text cross-attention and the feed-forward.
/// The official model accepts `audio=None` and skips that whole section, which is the forward
/// this block computes; a video-only pack has no audio weights to load. When the audio lane is
/// added it becomes an optional module on this block and an optional stream argument to
/// `callAsFunction`, nil today, and the video arithmetic above and below it does not change.
final class LTX2Block: Module {
    @ModuleInfo(key: "attn1") var selfAttention: LTX2GatedAttention
    @ModuleInfo(key: "attn2") var crossAttention: LTX2GatedAttention
    @ModuleInfo(key: "ff") var feedForward: LTX2FeedForward
    @ParameterInfo(key: "scale_shift_table") var table: MLXArray
    @ParameterInfo(key: "prompt_scale_shift_table") var promptTable: MLXArray

    private let eps: Float

    init(_ configuration: LTX2TransformerConfiguration) {
        let dim = configuration.innerDim
        eps = configuration.normEps
        _selfAttention.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: dim, heads: configuration.heads,
            headDim: configuration.headDim, eps: eps)
        _crossAttention.wrappedValue = LTX2GatedAttention(
            queryDim: dim, contextDim: configuration.crossAttentionDim, heads: configuration.heads,
            headDim: configuration.headDim, eps: eps)
        _feedForward.wrappedValue = LTX2FeedForward(
            dim: dim, hidden: configuration.feedForwardDim, bias: configuration.feedForwardBias)
        _table.wrappedValue = MLXArray.zeros([LTX2TransformerConfiguration.blockModulationRows, dim])
        _promptTable.wrappedValue = MLXArray.zeros([LTX2TransformerConfiguration.promptModulationRows, dim])
    }

    /// - Parameters:
    ///   - hidden: The video stream, `[batch, tokens, dim]`.
    ///   - text: The connector's output, `[batch, textTokens, crossAttentionDim]`.
    ///   - conditioning: The timestep's rows, shared by every block.
    ///   - rotary: The clip's rotary table, for the self-attention.
    ///   - textMask: An additive bias over the text tokens, or nil when every token counts.
    func callAsFunction(
        _ hidden: MLXArray,
        text: MLXArray,
        conditioning: LTX2BlockConditioning,
        rotary: LTX2RotaryTable,
        textMask: MLXArray? = nil
    ) -> MLXArray {
        let rows = Self.rows(table, conditioning.modulation, as: hidden.dtype)
        let promptRows = Self.rows(promptTable, conditioning.prompt, as: hidden.dtype)
        var x = hidden

        var normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[1]) + rows[0]
        x = x + selfAttention(normed, rotary: rotary) * rows[2]

        normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[7]) + rows[6]
        let context = text.asType(x.dtype) * (1 + promptRows[1]) + promptRows[0]
        x = x + crossAttention(normed, context: context, mask: textMask) * rows[8]

        normed = LTX2RMSNorm.normalize(x, eps: eps) * (1 + rows[4]) + rows[3]
        return x + feedForward(normed) * rows[5]
    }

    /// A `[rows, dim]` table added to the timestep's `[batch, 1, rows, dim]`, split into one
    /// `[batch, 1, dim]` per row and cast to the stream.
    static func rows(_ table: MLXArray, _ modulation: MLXArray, as dtype: DType) -> [MLXArray] {
        let summed = (table.asType(.float32) + modulation.asType(.float32)).asType(dtype)
        return (0..<table.shape[0]).map { summed[0..., 0..., $0, 0...] }
    }
}
