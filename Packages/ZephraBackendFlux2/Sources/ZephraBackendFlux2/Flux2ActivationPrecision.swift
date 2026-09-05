import Foundation
import MLX
import ZephraMLX

/// What klein's stream is held in on this Mac: bfloat16, unless the GPU is one the bug reaches.
///
/// mlx-swift up to 0.31.6 miscompiles a bfloat16 split-K matmul on M5-class GPUs at the
/// single-stream block's output shape (see `Flux2ParallelAttention`), so there the stream runs
/// float32 at three times the step time and never dispatches that kernel. Decided here, at the
/// backend's edge, and handed to `Flux2Pipeline.loadModel(at:activation:)`: the kit reads no
/// environment variable and asks no device. `ZEPHRA_DIT_DTYPE` overrides the gate either way —
/// `f32` on any Mac, `bf16` on an M5 — which is how the bug is bisected without a rebuild. The
/// gate is unverified: none of the project's Macs is an M5. `ROADMAP.md` says when it goes.
public enum Flux2ActivationPrecision {
    /// The dtype for the next load.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isM5Class: Bool = GPUGeneration.isM5Class
    ) -> DType {
        switch environment["ZEPHRA_DIT_DTYPE"] {
        case "f32": return .float32
        case "bf16": return .bfloat16
        default: return isM5Class ? .float32 : .bfloat16
        }
    }
}
