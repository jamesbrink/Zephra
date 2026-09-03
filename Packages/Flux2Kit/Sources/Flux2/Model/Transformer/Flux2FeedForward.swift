import Foundation
import MLX
import MLXNN

/// A dual-stream block's feed-forward network: a gated linear unit, written as one matrix.
///
/// `linear_in` is twice the hidden width because the gate and the value come out of the same
/// projection, and `Flux2SwiGLU` splits them apart. The reference calls that fusion out
/// explicitly; the consequence for us is that the checkpoint has two tensors here, not three,
/// and `linear_out` is half as wide on its input side as `linear_in` is on its output side.
///
/// Both linears are bias-free.
final class Flux2FeedForward: Module, UnaryLayer {
    @ModuleInfo(key: "linear_in") var input: Linear
    @ModuleInfo(key: "linear_out") var output: Linear

    /// - Parameters:
    ///   - dim: The model's width, in and out.
    ///   - hidden: The gated width, `dim * mlpRatio`.
    init(dim: Int, hidden: Int) {
        _input.wrappedValue = Linear(dim, hidden * 2, bias: false)
        _output.wrappedValue = Linear(hidden, dim, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        output(Self.swiglu(input(x)))
    }

    /// Splits the last axis in half and gates the second half by the first.
    ///
    /// The **first** half is the one that goes through the SiLU. Swapping them keeps every
    /// shape valid and quietly changes the function the block computes, so it is worth naming:
    /// this is `silu(x[..., :half]) * x[..., half:]`, matching the reference's `Flux2SwiGLU`.
    ///
    /// The single-stream block's fused projection reuses this, which is why it is static.
    static func swiglu(_ x: MLXArray) -> MLXArray {
        let half = x.shape[x.ndim - 1] / 2
        return silu(x[.ellipsis, ..<half]) * x[.ellipsis, half...]
    }
}
