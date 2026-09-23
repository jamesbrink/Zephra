import Foundation
import MLX
import MLXNN

/// A block's feed-forward half, `img_mlp`.
///
/// `mlp_ratio` is 3 and it is a **SwiGLU**, not a GELU feed-forward: three matrices, hidden
/// width `3 * dim`, `out(SiLU(gate_layer(h)) * proj(h))`. `proj` is the "up" and `gate_layer`
/// the "gate", which is the reference's naming and the naming an adapter's keys would use; a
/// port that swaps them applies the non-linearity to the wrong branch.
final class QwenImage21SwiGLUFeedForward: Module {
    @ModuleInfo(key: "proj") var up: Linear
    @ModuleInfo(key: "gate_layer") var gate: Linear
    @ModuleInfo(key: "out") var output: Linear

    init(dim: Int, hidden: Int) {
        _up.wrappedValue = Linear(dim, hidden, bias: false)
        _gate.wrappedValue = Linear(dim, hidden, bias: false)
        _output.wrappedValue = Linear(hidden, dim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(silu(gate(x)) * up(x))
    }
}
