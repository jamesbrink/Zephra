import Foundation
import MLX
import MLXNN
import ZephraMLX

/// FLUX.2's rectified-flow transformer: five dual-stream blocks, then twenty single-stream ones.
///
/// The shape of it is unusual in two ways worth knowing before reading the forward pass, which
/// lives in `Flux2Transformer+Forward.swift`.
///
/// First, the modulation is **shared**. Three projections at the top of the model produce every
/// shift, scale, and gate the twenty-five blocks use, computed once per step. So the blocks are
/// handed their modulation rather than owning it, and the checkpoint has three modulation
/// tensors rather than fifty.
///
/// Second, the single-stream blocks are parallel blocks: attention and feed-forward come out of
/// one fused projection and go back through one more. That is where the parameters are.
///
/// Every `Linear` in this component is bias-free. The checkpoint's 169 tensors are all
/// `.weight`, so building any of these with a bias makes the strict load fail on a tensor
/// nothing supplies.
public final class Flux2Transformer: Module {
    @ModuleInfo(key: "x_embedder") var imageInput: Linear
    @ModuleInfo(key: "context_embedder") var textInput: Linear
    @ModuleInfo(key: "time_guidance_embed") var timeEmbedding: Flux2TimeGuidanceEmbedding
    @ModuleInfo(key: "double_stream_modulation_img") var imageModulation: Flux2SharedModulation
    @ModuleInfo(key: "double_stream_modulation_txt") var textModulation: Flux2SharedModulation
    @ModuleInfo(key: "single_stream_modulation") var singleModulation: Flux2SharedModulation
    @ModuleInfo(key: "transformer_blocks") var doubleBlocks: [Flux2DoubleBlock]
    @ModuleInfo(key: "single_transformer_blocks") var singleBlocks: [Flux2SingleBlock]
    @ModuleInfo(key: "norm_out") var outputNorm: Flux2AdaLayerNormContinuous
    @ModuleInfo(key: "proj_out") var output: Linear

    /// Set when the dual-stream blocks' weights are read from disk on each pass rather than held.
    var doubleStream: LayerWeightStream<Flux2DoubleBlock>?
    /// Set when the single-stream blocks' weights are read from disk on each pass rather than
    /// held. Two streams and not one because the stacks are different types with different
    /// checkpoint names, and because the twenty single blocks are where the parameters are: a
    /// window over each stack is what keeps the shared modulation's five blocks from being read
    /// at the wrong end of the pass.
    var singleStream: LayerWeightStream<Flux2SingleBlock>?

    /// Builds the model described by `configuration`. Weights arrive separately, through
    /// `PackedWeightLoading.load(into:weights:manifest:checkpointName:)`.
    public init(_ configuration: Flux2TransformerConfiguration) {
        let dim = configuration.innerDim
        let eps = configuration.eps

        _imageInput.wrappedValue = Linear(configuration.inChannels, dim, bias: false)
        _textInput.wrappedValue = Linear(configuration.jointAttentionDim, dim, bias: false)
        _timeEmbedding.wrappedValue = Flux2TimeGuidanceEmbedding(
            embeddingDim: dim, channels: configuration.timestepGuidanceChannels)

        // Two sets for a dual-stream block's attention and feed-forward halves; one for a
        // single-stream block, which runs both halves at once.
        _imageModulation.wrappedValue = Flux2SharedModulation(dim: dim, sets: 2)
        _textModulation.wrappedValue = Flux2SharedModulation(dim: dim, sets: 2)
        _singleModulation.wrappedValue = Flux2SharedModulation(dim: dim, sets: 1)

        _doubleBlocks.wrappedValue = (0..<configuration.numLayers).map { _ in
            Flux2DoubleBlock(
                dim: dim,
                heads: configuration.numAttentionHeads,
                headDim: configuration.attentionHeadDim,
                mlpHidden: configuration.mlpDim,
                eps: eps)
        }
        _singleBlocks.wrappedValue = (0..<configuration.numSingleLayers).map { _ in
            Flux2SingleBlock(
                dim: dim,
                heads: configuration.numAttentionHeads,
                headDim: configuration.attentionHeadDim,
                mlpHidden: configuration.mlpDim,
                eps: eps)
        }

        _outputNorm.wrappedValue = Flux2AdaLayerNormContinuous(dim: dim, eps: eps)
        // The reference widens this by `patch_size` squared. FLUX.2's patch size is 1 and the
        // config does not carry it, because the 2x2 patching happens in the VAE's latent space
        // instead; see `Flux2LatentPacking`.
        _output.wrappedValue = Linear(dim, configuration.outChannels, bias: false)
    }
}
