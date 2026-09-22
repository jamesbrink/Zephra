import Foundation
import MLX
import MLXNN

/// The feed-forward in a tower block: a plain two-layer MLP, **not** SwiGLU.
///
/// The decoder's is gated and bias-free with three projections named `gate_proj`, `up_proj` and
/// `down_proj`; this one is two projections with biases named `linear_fc1` and `linear_fc2`,
/// and the activation between them is `gelu_pytorch_tanh` — the tanh approximation, which is
/// what `hidden_act` in `vision_config` names. The merger's own GELU is the **exact** one, and
/// the two are not interchangeable at this width.
final class Qwen3VLVisionFeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "linear_fc1") var first: Linear
    @ModuleInfo(key: "linear_fc2") var second: Linear

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        _first.wrappedValue = Linear(
            configuration.hiddenSize, configuration.intermediateSize, bias: true)
        _second.wrappedValue = Linear(
            configuration.intermediateSize, configuration.hiddenSize, bias: true)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray { second(geluApproximate(first(x))) }
}
