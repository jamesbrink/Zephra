import Foundation
import MLX
import MLXNN

/// The conditioning vector every block modulates by.
///
/// A wrapper with one child, matching the checkpoint's `time_text_embed.timestep_embedder.*`
/// naming. The name is a fossil of a version that also embedded pooled text; Qwen-Image-2512
/// conditions on the timestep alone.
final class QwenImageTimeTextEmbedding: Module {
    @ModuleInfo(key: "timestep_embedder") var timestep: QwenImageTimestepEmbedding

    init(embeddingDim: Int) {
        _timestep.wrappedValue = QwenImageTimestepEmbedding(embeddingDim: embeddingDim)
    }

    func callAsFunction(_ value: MLXArray) -> MLXArray {
        timestep(value)
    }
}
