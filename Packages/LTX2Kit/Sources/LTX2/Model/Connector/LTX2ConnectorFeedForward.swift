import Foundation
import MLX
import MLXNN

/// The connector block's feed-forward: a four-times expansion through tanh-GELU, with biases.
///
/// The reference builds this as `Sequential(GELU(proj), Dropout, Linear)`, so the checkpoint
/// numbers the two parameterised layers `net.0.proj` and `net.2`. Those positions are renamed
/// on the way in (see `LTX2ConnectorWeights`) rather than mirrored, because a module whose
/// children are numbered cannot be both loaded and quantized: MLX rebuilds a numeric path as an
/// array when it unflattens weights and as a dictionary when it replaces modules.
final class LTX2ConnectorFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "input") var input: Linear
    @ModuleInfo(key: "output") var output: Linear

    init(dim: Int, expansion: Int = 4) {
        _input.wrappedValue = Linear(dim, dim * expansion, bias: true)
        _output.wrappedValue = Linear(dim * expansion, dim, bias: true)
    }

    /// GELU's **tanh** approximation, which is what `gelu-approximate` means in the reference.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(geluApproximate(input(x)))
    }
}
