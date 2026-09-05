import Foundation
import MLX
import Testing

@testable import Flux2

extension TransformerParityTests {
    /// A canary for ml-explore/mlx#3797, not a test of this port.
    ///
    /// Up to mlx-swift 0.31.6 the split-K steel GEMM is JIT-compiled with the wrong dtype on
    /// M5-class GPUs, and it is dispatched only in half precision with a contraction of at
    /// least 10240. The single-stream block's `to_out` has K = 12288 and is inside that window
    /// at the token counts a 512-to-896-pixel generation produces, so this runs that exact
    /// shape. The stream runs in bfloat16 by default; on an M5 the backend's device gate (or
    /// `ZEPHRA_DIT_DTYPE=f32`) runs it float32, at three times the step time, and never
    /// dispatches the kernel. See `Flux2ParallelAttention`. The catalog variants pack `to_out`,
    /// so the production path is the quantized matmul the probe below runs rather than this
    /// dense one; whether it reaches the same kernel is not established.
    ///
    /// A failure here means either a regression or, on a fixed mlx-swift, nothing at all — the
    /// point is that a version bump reports the state of the bug instead of leaving it as
    /// folklore. Fixed upstream by ml-explore/mlx#3810 (mlx 0.32.0); no mlx-swift release
    /// carries it as of 2026-09-05.
    @Test("the fused output projection's bfloat16 matmul is finite at production width")
    func bfloat16OutputProbe() {
        let activations = MLXRandom.normal([1, 2816, 12288], key: MLXRandom.key(11))
        let weight = MLXRandom.normal([12288, 3072], key: MLXRandom.key(12))

        let reference = MLX.matmul(activations, weight)
        let packed = MLX.matmul(activations.asType(.bfloat16), weight.asType(.bfloat16))
            .asType(.float32)
        MLX.eval(reference, packed)

        #expect(MLX.all(MLX.isFinite(packed)).item(Bool.self))
        let scale = MLX.max(MLX.abs(reference)).item(Float.self)
        #expect(scale > 0)
        #expect(Fixture.maxAbsoluteDifference(packed, reference) / scale < 1e-1)
    }

    /// The same shape down the path the app actually takes. Both catalog variants pack `to_out`
    /// — 4-bit and 8-bit, group 64 — so a generation runs `quantizedMatmul` over bfloat16
    /// activations with bfloat16 scales, the way `PackedWeightLoading.castFloatParameters`
    /// leaves them. Whether that reaches the split-K kernel is exactly what is not established;
    /// the day an M5 runs this suite, the answer is here rather than in a picture.
    @Test(
        "the packed output projection's bfloat16 quantized matmul is finite at production width",
        arguments: [4, 8])
    func bfloat16QuantizedOutputProbe(bits: Int) {
        let groupSize = 64
        let activations = MLXRandom.normal([1, 2816, 12288], key: MLXRandom.key(13))
        let weight = MLXRandom.normal([3072, 12288], key: MLXRandom.key(14))
        let (wq, scales, biases) = MLX.quantized(weight, groupSize: groupSize, bits: bits)

        let reference = MLX.matmul(
            activations,
            MLX.dequantized(wq, scales: scales, biases: biases, groupSize: groupSize, bits: bits).T)
        let packed = MLX.quantizedMatmul(
            activations.asType(.bfloat16), wq,
            scales: scales.asType(.bfloat16), biases: biases?.asType(.bfloat16),
            transpose: true, groupSize: groupSize, bits: bits
        ).asType(.float32)
        MLX.eval(reference, packed)

        #expect(MLX.all(MLX.isFinite(packed)).item(Bool.self))
        let scale = MLX.max(MLX.abs(reference)).item(Float.self)
        #expect(scale > 0)
        #expect(Fixture.maxAbsoluteDifference(packed, reference) / scale < 1e-1)
    }
}
