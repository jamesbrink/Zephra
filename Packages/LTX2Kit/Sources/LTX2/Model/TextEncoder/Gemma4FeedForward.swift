import Foundation
import MLX
import MLXNN

/// The gated feed-forward network in a Gemma 4 decoder layer.
///
/// GeGLU with the tanh approximation of GELU (`gelu_pytorch_tanh`), not SiLU: the gate's
/// activation is the one place this differs from the Qwen stacks in the other kits, and a
/// swapped activation compiles and runs and conditions every video on slightly wrong text.
final class Gemma4FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "up_proj") var up: Linear
    @ModuleInfo(key: "down_proj") var down: Linear

    init(_ configuration: Gemma4Configuration) {
        let hidden = configuration.hiddenSize
        let intermediate = configuration.intermediateSize
        _gate.wrappedValue = Linear(hidden, intermediate, bias: false)
        _up.wrappedValue = Linear(hidden, intermediate, bias: false)
        _down.wrappedValue = Linear(intermediate, hidden, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(geluApproximate(gate(x)) * up(x))
    }
}
