import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Qwen-Image 2.1's rectified-flow transformer: 32 single-stream blocks over one joint sequence
/// of text and latents.
///
/// Three things about its shape are worth knowing before reading the forward pass, which is in
/// `QwenImage21Transformer+Forward.swift`.
///
/// **Modulation is shared.** One projection at the top produces the four vectors all 32 blocks
/// modulate by, so the checkpoint has one modulation tensor rather than 32 and the blocks own
/// none. See `QwenImage21SharedModulation`.
///
/// **There is no patchify.** `patch_size` is 1, so one token is one latent cell, `img_in` takes
/// the latent's own channels, and the `4` that appears in the layout is how many latent tokens
/// one *vision-language* image slot stands for, which is a different four entirely.
///
/// **Every linear is bias-free.** The checkpoint's 297 tensors are all `.weight`.
public final class QwenImage21Transformer: Module {
    @ModuleInfo(key: "img_in") var imageInput: Linear
    @ModuleInfo(key: "txt_in") var textInput: QwenImage21TextProjection
    @ModuleInfo(key: "time_text_embed") var timeEmbedding: QwenImage21TimestepEmbedding
    @ModuleInfo(key: "modulation") var modulation: QwenImage21SharedModulation
    @ModuleInfo(key: "transformer_blocks") var blocks: [QwenImage21TransformerBlock]
    @ModuleInfo(key: "norm_out") var outputNorm: QwenImage21AdaLayerNormContinuous
    @ModuleInfo(key: "proj_out") var output: Linear

    /// Set when the blocks' weights are read from disk on each pass rather than held.
    var blockStream: LayerWeightStream<QwenImage21TransformerBlock>?

    /// How many prefix caches a `QwenImage21KVCache` for this model needs.
    public var layerCount: Int { blocks.count }

    /// Whether the prefix is step-independent, and so whether a cache is valid at all.
    let causalCondition: Bool

    /// Builds the model described by `configuration`. Weights arrive separately, through
    /// `PackedWeightLoading.load(into:weights:manifest:checkpointName:)`.
    public init(_ configuration: QwenImage21TransformerConfiguration) {
        let dim = configuration.innerDim
        let eps = configuration.eps
        causalCondition = configuration.causalCondition

        // `in_channels * patch_size^2`, and the patch is one cell.
        _imageInput.wrappedValue = Linear(
            configuration.inChannels * configuration.patchSize * configuration.patchSize,
            dim, bias: false)
        _textInput.wrappedValue = QwenImage21TextProjection(
            contextDim: configuration.contextInDim, hidden: dim, eps: eps)
        _timeEmbedding.wrappedValue = QwenImage21TimestepEmbedding(embeddingDim: dim)
        _modulation.wrappedValue = QwenImage21SharedModulation(dim: dim)
        _blocks.wrappedValue = (0..<configuration.numLayers).map { _ in
            QwenImage21TransformerBlock(
                dim: dim,
                heads: configuration.numAttentionHeads,
                headDim: configuration.attentionHeadDim,
                mlpHidden: configuration.mlpHiddenSize,
                eps: eps)
        }
        _outputNorm.wrappedValue = QwenImage21AdaLayerNormContinuous(
            dim: dim, conditioningDim: dim, eps: eps)
        _output.wrappedValue = Linear(
            dim,
            configuration.patchSize * configuration.patchSize * configuration.outChannels,
            bias: false)
    }
}
