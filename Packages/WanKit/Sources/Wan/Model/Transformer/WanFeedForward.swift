import Foundation
import MLX
import MLXNN

/// A block's feed-forward network: up to `ffn_dim`, a tanh-approximated GELU, and back down,
/// both linears with biases (`FeedForward(activation_fn: "gelu-approximate")`).
///
/// The checkpoint spells the two linears `ffn.net.0.proj` and `ffn.net.2`, the indices of a
/// list with a dropout between them; `WanTransformerWeights` maps them onto `proj_in` and
/// `proj_out`.
final class WanFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "proj_in") var input: Linear
    @ModuleInfo(key: "proj_out") var output: Linear

    init(dim: Int, hidden: Int) {
        _input.wrappedValue = Linear(dim, hidden, bias: true)
        _output.wrappedValue = Linear(hidden, dim, bias: true)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(geluApproximate(input(x)))
    }
}
