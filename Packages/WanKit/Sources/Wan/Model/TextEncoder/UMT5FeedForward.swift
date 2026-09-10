import Foundation
import MLX
import MLXNN

/// UMT5's gated feed-forward, `DenseReluDense` in the checkpoint by a name older than the
/// activation it applies.
///
/// `gelu_new`, the tanh approximation of GELU, on the gate: the same curve as Gemma's
/// `gelu_pytorch_tanh`, and not the erf GELU the bare name `gelu` would give. The two agree
/// to a few thousandths and a swapped one still runs, so the parity fixture is what tells
/// them apart.
final class UMT5FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "wi_0") var gate: Linear
    @ModuleInfo(key: "wi_1") var up: Linear
    @ModuleInfo(key: "wo") var down: Linear

    init(_ configuration: UMT5Configuration) {
        _gate.wrappedValue = Linear(configuration.dModel, configuration.dFF, bias: false)
        _up.wrappedValue = Linear(configuration.dModel, configuration.dFF, bias: false)
        _down.wrappedValue = Linear(configuration.dFF, configuration.dModel, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(geluApproximate(gate(x)) * up(x))
    }
}
