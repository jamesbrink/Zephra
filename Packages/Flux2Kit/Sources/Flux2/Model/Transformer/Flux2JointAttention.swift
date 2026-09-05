import Foundation
import MLX
import MLXFast
import MLXNN
import ZephraMLX

/// Attention across both streams at once: text and image see each other here and nowhere else.
///
/// The two streams keep their own projections — `to_*` for the image, `add_*_proj` for the text
/// — and are then concatenated into one sequence, attended over jointly, and split apart again.
/// **Text goes first.** Splitting the result the other way round silently swaps the two streams'
/// outputs, and both halves are the right shape either way.
///
/// The rotary table covers the concatenated sequence, so it is applied after the concatenation,
/// not to each stream separately. That is the reason this takes one `frequencies` rather than
/// two: the text ids and the image ids were built into one table by the caller, and the rows
/// only line up if the queries are in that same order.
///
/// Every projection is bias-free.
final class Flux2JointAttention: Module {
    @ModuleInfo(key: "to_q") var imageQuery: Linear
    @ModuleInfo(key: "to_k") var imageKey: Linear
    @ModuleInfo(key: "to_v") var imageValue: Linear
    /// The reference wraps the image stream's output in a `ModuleList` with a dropout, so the
    /// checkpoint calls the linear `to_out.0`; that position is renamed on the way in, by
    /// `Flux2TransformerWeights`. The text stream's output is a bare linear already.
    @ModuleInfo(key: "to_out") var imageOutput: Linear

    @ModuleInfo(key: "add_q_proj") var textQuery: Linear
    @ModuleInfo(key: "add_k_proj") var textKey: Linear
    @ModuleInfo(key: "add_v_proj") var textValue: Linear
    @ModuleInfo(key: "to_add_out") var textOutput: Linear

    @ModuleInfo(key: "norm_q") var imageQueryNorm: RMSNorm
    @ModuleInfo(key: "norm_k") var imageKeyNorm: RMSNorm
    @ModuleInfo(key: "norm_added_q") var textQueryNorm: RMSNorm
    @ModuleInfo(key: "norm_added_k") var textKeyNorm: RMSNorm

    private let heads: Int
    private let headDim: Int
    private let scale: Float

    init(dim: Int, heads: Int, headDim: Int, eps: Float) {
        self.heads = heads
        self.headDim = headDim
        scale = 1 / sqrt(Float(headDim))

        for projection in [_imageQuery, _imageKey, _imageValue, _textQuery, _textKey, _textValue] {
            projection.wrappedValue = Linear(dim, heads * headDim, bias: false)
        }
        _imageOutput.wrappedValue = Linear(heads * headDim, dim, bias: false)
        _textOutput.wrappedValue = Linear(heads * headDim, dim, bias: false)
        for norm in [_imageQueryNorm, _imageKeyNorm, _textQueryNorm, _textKeyNorm] {
            norm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        }
    }

    /// Attends jointly and returns each stream's own output.
    func callAsFunction(
        image: MLXArray,
        text: MLXArray,
        frequencies: RotaryFrequencies
    ) -> (image: MLXArray, text: MLXArray) {
        let textLength = text.shape[1]

        // Heads are split out before the norms, which act on one head's width.
        let queries = joined(
            textQueryNorm(split(textQuery(text))), imageQueryNorm(split(imageQuery(image))))
        let keys = joined(
            textKeyNorm(split(textKey(text))), imageKeyNorm(split(imageKey(image))))
        let values = joined(split(textValue(text)), split(imageValue(image)))

        let attended = MLXFast.scaledDotProductAttention(
            queries: frequencies.rotate(queries, computeDType: .float32).transposed(0, 2, 1, 3),
            keys: frequencies.rotate(keys, computeDType: .float32).transposed(0, 2, 1, 3),
            values: values.transposed(0, 2, 1, 3),
            scale: scale,
            mask: nil
        )
        .transposed(0, 2, 1, 3)
        .reshaped([image.shape[0], -1, heads * headDim])

        return (
            image: imageOutput(attended[0..., textLength...]),
            text: textOutput(attended[0..., ..<textLength])
        )
    }

    /// Text first, then image: the order the rotary table and the final split both assume.
    private func joined(_ text: MLXArray, _ image: MLXArray) -> MLXArray {
        MLX.concatenated([text, image], axis: 1)
    }

    /// `[batch, tokens, heads * headDim]` into `[batch, tokens, heads, headDim]`.
    private func split(_ x: MLXArray) -> MLXArray {
        x.reshaped([x.shape[0], x.shape[1], heads, headDim])
    }
}
