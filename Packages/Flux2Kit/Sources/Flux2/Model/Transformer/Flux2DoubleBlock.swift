import Foundation
import MLX
import MLXNN

/// One dual-stream block, instantiated five times.
///
/// Both streams run the same shape of work — modulate, attend or feed forward, gate back into
/// the residual — but each keeps its own projections and its own residual. They meet only
/// inside the attention.
///
/// The modulation arrives as an argument rather than being a child of this block: FLUX.2
/// computes it once for the whole forward pass and every dual-stream block reads the same
/// numbers. See `Flux2SharedModulation`.
///
/// The four layer norms have nothing learned, which is why the checkpoint carries no weights
/// for them.
final class Flux2DoubleBlock: Module {
    @ModuleInfo(key: "attn") var attention: Flux2JointAttention
    @ModuleInfo(key: "ff") var imageFeedForward: Flux2FeedForward
    @ModuleInfo(key: "ff_context") var textFeedForward: Flux2FeedForward

    private let eps: Float

    init(dim: Int, heads: Int, headDim: Int, mlpHidden: Int, eps: Float) {
        _attention.wrappedValue = Flux2JointAttention(
            dim: dim, heads: heads, headDim: headDim, eps: eps)
        _imageFeedForward.wrappedValue = Flux2FeedForward(dim: dim, hidden: mlpHidden)
        _textFeedForward.wrappedValue = Flux2FeedForward(dim: dim, hidden: mlpHidden)
        self.eps = eps
    }

    /// - Parameters:
    ///   - image: The image stream, `[batch, imageTokens, dim]`.
    ///   - text: The text stream, `[batch, textTokens, dim]`.
    ///   - imageModulation: Two sets for the image stream: attention first, feed-forward second.
    ///   - textModulation: The same two, for the text stream.
    ///   - frequencies: The rotary table over the concatenated `[text, image]` sequence.
    func callAsFunction(
        image: MLXArray,
        text: MLXArray,
        imageModulation: [Flux2SharedModulation.Parameters],
        textModulation: [Flux2SharedModulation.Parameters],
        frequencies: RotaryFrequencies
    ) -> (image: MLXArray, text: MLXArray) {
        let attended = attention(
            image: imageModulation[0].modulate(Flux2LayerNorm.applied(to: image, eps: eps)),
            text: textModulation[0].modulate(Flux2LayerNorm.applied(to: text, eps: eps)),
            frequencies: frequencies
        )
        var imageStream = image + imageModulation[0].gate * attended.image
        var textStream = text + textModulation[0].gate * attended.text

        imageStream =
            imageStream
            + imageModulation[1].gate
            * imageFeedForward(
                imageModulation[1].modulate(Flux2LayerNorm.applied(to: imageStream, eps: eps)))
        textStream =
            textStream
            + textModulation[1].gate
            * textFeedForward(
                textModulation[1].modulate(Flux2LayerNorm.applied(to: textStream, eps: eps)))

        return (image: imageStream, text: textStream)
    }
}
