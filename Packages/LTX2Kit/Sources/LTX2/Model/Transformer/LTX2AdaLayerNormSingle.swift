import Foundation
import MLX
import MLXNN

/// One timestep embedding fanned out into a set of modulation rows: PixArt's adaLN-single
/// with a configurable row count, which LTX-2 uses for the blocks (nine rows), the prompt's
/// keys and values (two) and, in the audio-video model, the cross-modal gates.
///
/// The embedding itself is also handed back, because the output head modulates by the raw
/// embedded timestep rather than by any of the rows.
final class LTX2AdaLayerNormSingle: Module {
    @ModuleInfo(key: "emb") var embedding: LTX2TimestepEmbedding
    @ModuleInfo(key: "linear") var fanOut: Linear

    /// How many `[dim]` rows `callAsFunction` produces per batch element.
    let rows: Int

    init(dim: Int, rows: Int, timestepScale: Float) {
        self.rows = rows
        _embedding.wrappedValue = LTX2TimestepEmbedding(embeddingDim: dim, timestepScale: timestepScale)
        _fanOut.wrappedValue = Linear(dim, rows * dim, bias: true)
    }

    /// For `sigma` of shape `[batch]`: the modulation as `[batch, 1, rows, dim]`, ready to be
    /// added to a `[rows, dim]` table, and the embedded timestep as `[batch, 1, dim]`.
    func callAsFunction(_ sigma: MLXArray, dtype: DType) -> (modulation: MLXArray, embedded: MLXArray) {
        let embedded = embedding(sigma, dtype: dtype)
        let batch = embedded.shape[0]
        let modulation = fanOut(silu(embedded)).reshaped([batch, 1, rows, -1])
        return (modulation, embedded.reshaped([batch, 1, -1]))
    }
}
