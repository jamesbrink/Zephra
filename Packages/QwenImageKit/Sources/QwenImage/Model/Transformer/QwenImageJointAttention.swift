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
/// Rotation here pairs adjacent channels, unlike the text encoder's half-split.
final class QwenImageJointAttention: Module {
    @ModuleInfo(key: "to_q") var imageQuery: Linear
    @ModuleInfo(key: "to_k") var imageKey: Linear
    @ModuleInfo(key: "to_v") var imageValue: Linear
    /// The reference builds the image stream's output as `Sequential(Linear, Dropout)`, so the
    /// checkpoint calls the linear `to_out.0`; that position is renamed on the way in. The text
    /// stream's output is a bare linear and is already named `to_add_out`.
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

    init(dim: Int, heads: Int, headDim: Int, eps: Float = 1e-6) {
        self.heads = heads
        self.headDim = headDim
        scale = 1 / sqrt(Float(headDim))

        for projection in [_imageQuery, _imageKey, _imageValue, _textQuery, _textKey, _textValue] {
            projection.wrappedValue = Linear(dim, heads * headDim, bias: true)
        }
        _imageOutput.wrappedValue = Linear(heads * headDim, dim, bias: true)
        _textOutput.wrappedValue = Linear(heads * headDim, dim, bias: true)
        for norm in [_imageQueryNorm, _imageKeyNorm, _textQueryNorm, _textKeyNorm] {
            norm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        }
    }

    /// Attends jointly and returns each stream's own output.
    func callAsFunction(
        image: MLXArray,
        text: MLXArray,
        imageFrequencies: RotaryFrequencies,
        textFrequencies: RotaryFrequencies
    ) -> (image: MLXArray, text: MLXArray) {
        let textLength = text.shape[1]

        // Heads are split out before the norms, which act on one head's width.
        let imageQueries = imageFrequencies.rotate(imageQueryNorm(split(imageQuery(image))), computeDType: image.dtype)
        let imageKeys = imageFrequencies.rotate(imageKeyNorm(split(imageKey(image))), computeDType: image.dtype)
        let imageValues = split(imageValue(image))

        let textQueries = textFrequencies.rotate(textQueryNorm(split(textQuery(text))), computeDType: text.dtype)
        let textKeys = textFrequencies.rotate(textKeyNorm(split(textKey(text))), computeDType: text.dtype)
        let textValues = split(textValue(text))

        // Text first, then image: the order the split at the end undoes.
        let queries = MLX.concatenated([textQueries, imageQueries], axis: 1).transposed(0, 2, 1, 3)
        let keys = MLX.concatenated([textKeys, imageKeys], axis: 1).transposed(0, 2, 1, 3)
        let values = MLX.concatenated([textValues, imageValues], axis: 1).transposed(0, 2, 1, 3)

        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: nil
        )
        .transposed(0, 2, 1, 3)
        .reshaped([image.shape[0], -1, heads * headDim])

        return (
            image: imageOutput(attended[0..., textLength...]),
            text: textOutput(attended[0..., ..<textLength])
        )
    }

    /// `[batch, tokens, heads * headDim]` into `[batch, tokens, heads, headDim]`.
    private func split(_ x: MLXArray) -> MLXArray {
        x.reshaped([x.shape[0], x.shape[1], heads, headDim])
    }
}
