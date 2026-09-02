import Foundation
import MLX
import MLXNN

/// The gated feed-forward network in a Qwen2.5 decoder layer.
///
/// SwiGLU: one projection is squashed by SiLU and gates the other. All three projections are
/// bias-free, unlike the attention's.
final class Qwen25FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "up_proj") var up: Linear
    @ModuleInfo(key: "down_proj") var down: Linear

    init(_ configuration: QwenImageTextEncoderConfiguration) {
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
