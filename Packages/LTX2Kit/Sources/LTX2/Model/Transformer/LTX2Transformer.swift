import Foundation
import MLX
import MLXNN
import ZephraMLX

/// LTX-2's video transformer: forty-eight blocks over a clip's latent tokens, conditioned on
/// the text connector's output and on the noise level.
///
/// The video lane always, and the audio lane when the configuration names one: its ends and
/// conditioners are `LTX2AudioHead` under `audio`, its blocks' halves `LTX2AudioLane` under
/// each block's `audio`, both nil on a video-only tree, which loads and runs exactly as it
/// did before the lane existed.
public final class LTX2Transformer: Module {
    @ModuleInfo(key: "patchify_proj") var patchify: Linear
    @ModuleInfo(key: "adaln_single") var timestepModulation: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "prompt_adaln_single") var promptModulation: LTX2AdaLayerNormSingle
    @ModuleInfo(key: "transformer_blocks") var blocks: [LTX2Block]
    @ModuleInfo(key: "proj_out") var output: Linear
    /// Shift and scale for the output head, `[2, dim]`, added to the embedded timestep.
    @ParameterInfo(key: "scale_shift_table") var outputTable: MLXArray
    /// Added to every token whose latent cell holds a single pixel frame: the first latent
    /// frame of any clip, because the autoencoder is causal, and a generated keyframe slot. The
    /// reference marks the first frame unconditionally, and so does this.
    @ParameterInfo(key: "keyframes_abs_pos_embedding") var keyframeEmbedding: MLXArray
    /// The audio lane's ends and conditioners, or nil on a video-only tree.
    @ModuleInfo(key: "audio") var audioHead: LTX2AudioHead?

    let configuration: LTX2TransformerConfiguration
    /// The rotary embedding over the clip's three axes.
    public let rotary: LTX2RotaryEmbedding

    /// Set when the blocks' weights are read from disk on every step rather than held. The
    /// loop then hands each block to the stream, which has its weights in memory for exactly
    /// as long as the block runs.
    var stream: LayerWeightStream<LTX2Block>?

    /// How many blocks run between evaluations of the stream when the weights are resident: a
    /// Metal command buffer that runs longer than the watchdog allows is killed, and forty-eight
    /// blocks of a 22B model in one buffer can be. The reference port flushes every eight.
    public var blocksPerEval = 8

    /// Builds the model described by `configuration`. Weights arrive separately.
    public init(_ configuration: LTX2TransformerConfiguration) {
        self.configuration = configuration
        let dim = configuration.innerDim
        rotary = LTX2RotaryEmbedding(
            heads: configuration.heads, headDim: configuration.headDim,
            maxPositions: configuration.ropeMaxPositions, theta: configuration.ropeTheta)
        _patchify.wrappedValue = Linear(configuration.inChannels, dim, bias: true)
        _timestepModulation.wrappedValue = LTX2AdaLayerNormSingle(
            dim: dim, rows: LTX2TransformerConfiguration.blockModulationRows,
            timestepScale: configuration.timestepScale)
        _promptModulation.wrappedValue = LTX2AdaLayerNormSingle(
            dim: dim, rows: LTX2TransformerConfiguration.promptModulationRows,
            timestepScale: configuration.timestepScale)
        _blocks.wrappedValue = (0..<configuration.layers).map { _ in LTX2Block(configuration) }
        _output.wrappedValue = Linear(dim, configuration.outChannels, bias: true)
        _outputTable.wrappedValue = MLXArray.zeros([2, dim])
        _keyframeEmbedding.wrappedValue = MLXArray.zeros([1, dim])
        _audioHead.wrappedValue = configuration.audio.map { LTX2AudioHead(configuration, audio: $0) }
    }

    /// Whether the tree carries the audio lane.
    public var hasAudio: Bool { audioHead != nil }
}
