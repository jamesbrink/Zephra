import Foundation
import MLX
import MLXNN

/// The two-layer projection that widens the sinusoid to the model's width, `timestep_embedder`.
///
/// `linear_2(SiLU(linear_1(x)))`, both bias-free like every linear in this transformer. Split
/// from `QwenImage21TimestepEmbedding` because the checkpoint names it as its own module, and a
/// module path with a dot in it is not a key MLX will take.
final class QwenImage21TimestepProjection: Module {
    @ModuleInfo(key: "linear_1") var input: Linear
    @ModuleInfo(key: "linear_2") var output: Linear

    init(channels: Int, embeddingDim: Int) {
        _input.wrappedValue = Linear(channels, embeddingDim, bias: false)
        _output.wrappedValue = Linear(embeddingDim, embeddingDim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(silu(input(x)))
    }
}
