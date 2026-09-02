import Foundation
import MLX
import MLXNN

/// One dual-stream MMDiT block, instantiated sixty times.
///
/// Both streams run the same shape of work — modulate, attend or feed forward, gate back into
/// the residual — but each keeps its own modulation, its own projections, and its own residual.
/// They meet only inside the attention.
///
/// The two layer norms have no learnable parameters, which is why the checkpoint carries no
/// weights for them.
final class QwenImageTransformerBlock: Module {
    @ModuleInfo(key: "img_mod") var imageModulation: [Module]
    @ModuleInfo(key: "txt_mod") var textModulation: [Module]
    @ModuleInfo(key: "attn") var attention: QwenImageJointAttention
    @ModuleInfo(key: "img_mlp") var imageFeedForward: QwenImageFeedForward
    @ModuleInfo(key: "txt_mlp") var textFeedForward: QwenImageFeedForward

    private let norm: LayerNorm

    init(dim: Int, heads: Int, headDim: Int, eps: Float = 1e-6) {
        _imageModulation.wrappedValue = QwenImageStreamModulation.slots(dim: dim)
        _textModulation.wrappedValue = QwenImageStreamModulation.slots(dim: dim)
        _attention.wrappedValue = QwenImageJointAttention(
            dim: dim, heads: heads, headDim: headDim, eps: eps)
        _imageFeedForward.wrappedValue = QwenImageFeedForward(dim: dim)
        _textFeedForward.wrappedValue = QwenImageFeedForward(dim: dim)
        norm = LayerNorm(dimensions: dim, eps: eps, affine: false)
    }

    func callAsFunction(
        image: MLXArray,
        text: MLXArray,
        conditioning: MLXArray,
        imageFrequencies: RotaryFrequencies,
        textFrequencies: RotaryFrequencies
    ) -> (image: MLXArray, text: MLXArray) {
        let imageParameters = QwenImageStreamModulation.parameters(imageModulation, conditioning)
        let textParameters = QwenImageStreamModulation.parameters(textModulation, conditioning)

        let attended = attention(
            image: imageParameters.attention.modulate(norm(image)),
            text: textParameters.attention.modulate(norm(text)),
            imageFrequencies: imageFrequencies,
            textFrequencies: textFrequencies
        )
        var imageStream = image + imageParameters.attention.gate * attended.image
        var textStream = text + textParameters.attention.gate * attended.text

        imageStream =
            imageStream
            + imageParameters.feedForward.gate
            * imageFeedForward(imageParameters.feedForward.modulate(norm(imageStream)))
        textStream =
            textStream
            + textParameters.feedForward.gate
            * textFeedForward(textParameters.feedForward.modulate(norm(textStream)))

        return (image: imageStream, text: textStream)
    }
}
