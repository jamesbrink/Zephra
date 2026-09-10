import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Wan 2.2's video transformer: thirty blocks over a clip's latent tokens, conditioned on the
/// text embeddings and on a per-token timestep (`WanTransformer3DModel`, TI2V-5B).
///
/// The module tree's parameter paths are the checkpoint's tensor names, three renames apart
/// (`WanTransformerWeights`), so the packed variant loads by name and the weight stream can
/// find every block's tensors in the shards.
public final class WanTransformer: Module {
    @ModuleInfo(key: "patch_embedding") var patchEmbedding: WanPatchEmbedding
    @ModuleInfo(key: "condition_embedder") var conditionEmbedder: WanConditionEmbedder
    @ModuleInfo(key: "blocks") var blocks: [WanTransformerBlock]
    @ModuleInfo(key: "proj_out") var output: Linear
    /// Shift and scale for the output head, `[1, 2, dim]`, added to the embedded timestep.
    @ParameterInfo(key: "scale_shift_table") var outputTable: MLXArray

    let configuration: WanTransformerConfiguration
    /// The rotary embedding over the clip's three axes.
    public let rotary: WanRotaryEmbedding
    /// The table for the last grid a forward ran on, reused while the grid stays the same.
    private var table: WanRotaryTable?

    /// Set when the blocks' weights are read from disk on every step rather than held. The
    /// loop then hands each block to the stream, which has its weights in memory for exactly
    /// as long as the block runs.
    var stream: LayerWeightStream<WanTransformerBlock>?

    /// How many blocks run between evaluations when the weights are resident: a Metal
    /// command buffer that runs longer than the watchdog allows is killed, and thirty blocks
    /// over a long clip in one buffer can be. Eight, as LTX-2.5 flushes.
    public var blocksPerEval = 8

    /// Builds the model described by `configuration`. Weights arrive separately.
    public init(_ configuration: WanTransformerConfiguration) {
        self.configuration = configuration
        let dim = configuration.innerDim
        rotary = WanRotaryEmbedding(
            headDim: configuration.attentionHeadDim, maxSeqLen: configuration.ropeMaxSeqLen)
        _patchEmbedding.wrappedValue = WanPatchEmbedding(
            inChannels: configuration.inChannels, dim: dim, patch: configuration.patchSize)
        _conditionEmbedder.wrappedValue = WanConditionEmbedder(configuration)
        _blocks.wrappedValue = (0..<configuration.numLayers).map { _ in WanTransformerBlock(configuration) }
        _output.wrappedValue = Linear(dim, configuration.patchValues, bias: true)
        _outputTable.wrappedValue = MLXArray.zeros([1, WanTransformerConfiguration.headModulationRows, dim])
    }

    /// The rotary table for a grid, built once per shape.
    func rotaryTable(frames: Int, height: Int, width: Int) -> WanRotaryTable {
        if let table, table.covers(frames: frames, height: height, width: width) { return table }
        let built = rotary.table(frames: frames, height: height, width: width)
        table = built
        return built
    }
}
