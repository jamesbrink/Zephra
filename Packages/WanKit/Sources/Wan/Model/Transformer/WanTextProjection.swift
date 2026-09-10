import Foundation
import MLX
import MLXNN

/// Projects the text encoder's embeddings into the stream: a linear, a tanh-approximated GELU,
/// a linear, both with biases (`PixArtAlphaTextProjection(act_fn: "gelu_tanh")`).
final class WanTextProjection: Module {
    @ModuleInfo(key: "linear_1") var input: Linear
    @ModuleInfo(key: "linear_2") var output: Linear

    init(textDim: Int, dim: Int) {
        _input.wrappedValue = Linear(textDim, dim, bias: true)
        _output.wrappedValue = Linear(dim, dim, bias: true)
    }

    /// `[batch, textTokens, textDim]` to `[batch, textTokens, dim]`.
    func callAsFunction(_ text: MLXArray) -> MLXArray {
        output(geluApproximate(input(text)))
    }
}
