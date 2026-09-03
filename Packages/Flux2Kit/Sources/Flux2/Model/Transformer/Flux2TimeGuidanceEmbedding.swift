import Foundation
import MLX
import MLXNN

/// The conditioning vector, under the checkpoint's own naming.
///
/// A wrapper with exactly one child, mirroring `time_guidance_embed.timestep_embedder.*`. The
/// alternative is to rewrite that prefix away on the way in, and mirroring is cheaper: a rename
/// has to be undone again for the quantization manifest, which knows layers by their checkpoint
/// names.
///
/// The name promises a guidance embedder as well, and the architecture has one — but klein is
/// distilled, its config says `guidance_embeds: false`, and no such tensor exists in the
/// checkpoint. Building one anyway would make the strict load fail on a weight nothing supplies.
final class Flux2TimeGuidanceEmbedding: Module {
    @ModuleInfo(key: "timestep_embedder") var timestep: Flux2TimestepEmbedding

    init(embeddingDim: Int, channels: Int) {
        _timestep.wrappedValue = Flux2TimestepEmbedding(
            embeddingDim: embeddingDim, channels: channels)
    }

    func callAsFunction(_ value: MLXArray) -> MLXArray {
        timestep(value)
    }
}
