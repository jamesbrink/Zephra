import Foundation
import MLX
import MLXNN

/// What the blocks are conditioned on: the timestep, embedded and fanned out into six
/// modulation rows, and the text, projected into the stream (`WanTimeTextImageEmbedding`
/// without its image path, which TI2V-5B has not got).
///
/// The timestep is embedded in float32 and cast to the stream, and the six rows come from
/// `time_proj`, a SiLU and a linear, in the stream's dtype: the order the reference casts in
/// under a bfloat16 load.
final class WanConditionEmbedder: Module {
    @ModuleInfo(key: "time_embedder") var timestepEmbedding: WanTimestepEmbedding
    @ModuleInfo(key: "time_proj") var fanOut: Linear
    @ModuleInfo(key: "text_embedder") var textProjection: WanTextProjection

    private let rows = WanTransformerConfiguration.blockModulationRows

    init(_ configuration: WanTransformerConfiguration) {
        let dim = configuration.innerDim
        _timestepEmbedding.wrappedValue = WanTimestepEmbedding(
            frequencyChannels: configuration.freqDim, embeddingDim: dim)
        _fanOut.wrappedValue = Linear(dim, rows * dim, bias: true)
        _textProjection.wrappedValue = WanTextProjection(textDim: configuration.textDim, dim: dim)
    }

    /// For `timesteps` of shape `[count]`: the embedded timestep as `[count, dim]`, the
    /// modulation as `[count, 6, dim]`, and the text as `[batch, textTokens, dim]`, all in
    /// `dtype`.
    func callAsFunction(
        _ timesteps: MLXArray, text: MLXArray, dtype: DType
    ) -> (embedded: MLXArray, modulation: MLXArray, text: MLXArray) {
        let embedded = timestepEmbedding(timesteps).asType(dtype)
        let modulation = fanOut(silu(embedded)).reshaped([embedded.shape[0], rows, -1])
        return (embedded, modulation, textProjection(text.asType(dtype)))
    }
}
