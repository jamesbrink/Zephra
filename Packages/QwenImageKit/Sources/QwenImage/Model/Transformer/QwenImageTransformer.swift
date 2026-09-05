import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Qwen-Image's MMDiT: sixty dual-stream blocks over a packed latent and a text stream.
///
/// The timestep arrives on a zero-to-one scale — the pipeline divides by the training steps
/// before calling — and the sinusoid scales it back up.
public final class QwenImageTransformer: Module {
    @ModuleInfo(key: "img_in") var imageInput: Linear
    @ModuleInfo(key: "txt_norm") var textNorm: RMSNorm
    @ModuleInfo(key: "txt_in") var textInput: Linear
    @ModuleInfo(key: "time_text_embed") var timeEmbedding: QwenImageTimeTextEmbedding
    @ModuleInfo(key: "transformer_blocks") var blocks: [QwenImageTransformerBlock]
    @ModuleInfo(key: "norm_out") var outputNorm: QwenImageAdaLayerNormContinuous
    @ModuleInfo(key: "proj_out") var output: Linear

    private let configuration: QwenImageTransformerConfiguration

    /// Set when the blocks' weights are read from disk on every step rather than held. The
    /// loop below then hands each block to the stream, which has its weights in memory for
    /// exactly as long as the block runs.
    var stream: LayerWeightStream<QwenImageTransformerBlock>?

    /// Builds the model described by `configuration`. Weights arrive separately.
    public init(_ configuration: QwenImageTransformerConfiguration) {
        self.configuration = configuration
        let dim = configuration.innerDim
        _imageInput.wrappedValue = Linear(configuration.inChannels, dim, bias: true)
        _textNorm.wrappedValue = RMSNorm(dimensions: configuration.jointAttentionDim, eps: 1e-6)
        _textInput.wrappedValue = Linear(configuration.jointAttentionDim, dim, bias: true)
        _timeEmbedding.wrappedValue = QwenImageTimeTextEmbedding(embeddingDim: dim)
        _blocks.wrappedValue = (0..<configuration.numLayers).map { _ in
            QwenImageTransformerBlock(
                dim: dim,
                heads: configuration.numAttentionHeads,
                headDim: configuration.attentionHeadDim
            )
        }
        _outputNorm.wrappedValue = QwenImageAdaLayerNormContinuous(dim: dim)
        _output.wrappedValue = Linear(
            dim,
            configuration.patchSize * configuration.patchSize * configuration.outChannels,
            bias: true
        )
    }

    /// Predicts the flow for one step.
    ///
    /// - Parameters:
    ///   - latents: Packed patch tokens, `[batch, imageTokens, inChannels]`.
    ///   - text: Conditioning from the encoder, `[batch, textTokens, jointAttentionDim]`.
    ///   - timestep: The noise level, from zero to one.
    ///   - frequencies: Rotary tables for both streams, sized to this image and prompt.
    ///
    /// Throws only when streaming: a shard that changed under the model, or a stop between
    /// blocks. A resident run has nothing to throw.
    public func callAsFunction(
        latents: MLXArray,
        text: MLXArray,
        timestep: MLXArray,
        frequencies: (image: RotaryFrequencies, text: RotaryFrequencies)
    ) throws -> MLXArray {
        var image = imageInput(latents)
        var textStream = textInput(textNorm(text))
        let conditioning = timeEmbedding(timestep).asType(image.dtype)

        let step = { (block: QwenImageTransformerBlock) in
            (image, textStream) = block(
                image: image,
                text: textStream,
                conditioning: conditioning,
                imageFrequencies: frequencies.image,
                textFrequencies: frequencies.text
            )
        }
        if let stream {
            // A streamed step is tens of seconds on the Mac that needs it, so a stop is
            // answered between blocks rather than at the step's end.
            try stream.run { block in
                try Task.checkCancellation()
                step(block)
                return [image, textStream]
            }
        } else {
            for block in blocks { step(block) }
        }

        return output(outputNorm(image, conditioning: conditioning))
    }
}
