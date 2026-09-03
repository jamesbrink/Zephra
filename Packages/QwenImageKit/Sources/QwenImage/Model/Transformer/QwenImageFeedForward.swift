import Foundation
import MLX
import MLXNN

/// A block's feed-forward network: widen fourfold, gate with GELU, narrow back.
///
/// The reference builds this as `Sequential(GELU(proj), Dropout, Linear)`, so the checkpoint
/// numbers the two parameterised layers `0` and `2`. Those positions are renamed on the way in
/// (see `QwenImageTransformerWeights`) rather than mirrored, because a module whose children are
/// numbered cannot be both loaded and quantized: MLX rebuilds a numeric path as an array when it
/// unflattens weights and as a dictionary when it replaces modules, and the two do not meet.
final class QwenImageFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "input") var input: Linear
    @ModuleInfo(key: "output") var output: Linear

    init(dim: Int, expansion: Int = 4) {
        _input.wrappedValue = Linear(dim, dim * expansion, bias: true)
        _output.wrappedValue = Linear(dim * expansion, dim, bias: true)
    }

    /// GELU's **tanh** approximation, which is what `gelu-approximate` means in the reference.
    /// MLX's plain `gelu` is the exact erf form and differs by enough to matter.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(geluApproximate(input(x)))
    }
}
