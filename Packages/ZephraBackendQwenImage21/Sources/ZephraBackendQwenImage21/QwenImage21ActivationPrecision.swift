import MLX
import ZephraCore
import ZephraMLX

/// What 2.1's stream is held in on this Mac: bfloat16, unless the GPU is one the bug reaches.
///
/// mlx-swift up to 0.31.6 miscompiles a bfloat16 split-K matmul on M5-class GPUs, so there the
/// stream runs float32 and never dispatches that kernel. Decided here, at the backend's edge,
/// and handed to `QwenImage21Pipeline.loadModel(at:activation:streaming:)`: the kit reads no
/// environment variable and asks no device, which is why `QwenImage21TransformerPrecision`
/// carries only the default. `ZEPHRA_DIT_DTYPE`, read once at the composition root into
/// `InferenceEnvironment.ditFloat32`, overrides the gate either way — `f32` on any Mac, `bf16`
/// on an M5 — which is how the bug is bisected without a rebuild. The gate is unverified: none
/// of the project's Macs is an M5. `ROADMAP.md` says when it goes.
///
/// Deliberately a copy of `Flux2ActivationPrecision` rather than a shared type: no backend
/// package may import another, and the day klein's gate lifts this one may not.
public enum QwenImage21ActivationPrecision {
    /// The dtype for the next load.
    public static func resolve(
        environment: InferenceEnvironment,
        isM5Class: Bool = GPUGeneration.isM5Class
    ) -> DType {
        switch environment.ditFloat32 {
        case true?: return .float32
        case false?: return .bfloat16
        case nil: return isM5Class ? .float32 : .bfloat16
        }
    }
}
