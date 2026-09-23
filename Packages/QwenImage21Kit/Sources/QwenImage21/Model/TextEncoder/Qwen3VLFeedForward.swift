import Foundation
import MLX
import MLXNN

/// The gated feed-forward in a Qwen3-VL decoder layer.
///
/// SwiGLU, 12,288 wide: one projection is squashed by SiLU and gates the other. All three are
/// bias-free, as is every linear in this stack.
///
/// The tower's feed-forward is deliberately **not** this shape — it is a plain two-layer
/// GELU-tanh MLP named `linear_fc1`/`linear_fc2` — which is why the two are separate files
/// rather than one parameterised by an activation.
final class Qwen3VLFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "up_proj") var up: Linear
    @ModuleInfo(key: "down_proj") var down: Linear

    init(_ configuration: Qwen3VLTextConfiguration.Text) {
        let hidden = configuration.hiddenSize
        let intermediate = configuration.intermediateSize
        _gate.wrappedValue = Linear(hidden, intermediate, bias: false)
        _up.wrappedValue = Linear(hidden, intermediate, bias: false)
        _down.wrappedValue = Linear(intermediate, hidden, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(silu(gate(x)) * up(x))
    }
}
