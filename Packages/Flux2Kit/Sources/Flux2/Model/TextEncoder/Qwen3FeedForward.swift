import Foundation
import MLX
import MLXNN

/// The gated feed-forward network in a Qwen3 decoder layer.
///
/// SwiGLU: one projection is squashed by SiLU and gates the other. All three projections are
/// bias-free, as is every linear in this stack -- Qwen3 sets `attention_bias` false and carries
/// no bias tensor anywhere, which the weight-key coverage test pins.
final class Qwen3FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "up_proj") var up: Linear
    @ModuleInfo(key: "down_proj") var down: Linear

    init(_ configuration: Flux2TextEncoderConfiguration) {
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
