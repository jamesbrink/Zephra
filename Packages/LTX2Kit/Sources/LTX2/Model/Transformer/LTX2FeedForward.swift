import Foundation
import MLX
import MLXNN

/// A block's feed-forward network: up four times, a tanh-approximated GELU, and back down.
///
/// The two linears have no biases on LTX-2.5 (`ff_bias: false`), where every earlier LTX-2
/// had them; the flag is a parameter so a doll's-house fixture can be dumped either way and so
/// the audio lane, which keeps its biases, can share the type. The activation is the
/// `gelu-approximate` the configuration asserts, which is the tanh form and not the
/// `x * sigmoid(1.702 x)` shortcut.
final class LTX2FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "proj_in") var input: Linear
    @ModuleInfo(key: "proj_out") var output: Linear

    init(dim: Int, hidden: Int, bias: Bool) {
        _input.wrappedValue = Linear(dim, hidden, bias: bias)
        _output.wrappedValue = Linear(hidden, dim, bias: bias)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(geluApproximate(input(x)))
    }
}
