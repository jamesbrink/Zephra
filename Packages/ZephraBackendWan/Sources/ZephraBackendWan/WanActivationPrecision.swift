import MLX
import ZephraCore

/// What Wan 2.2's stream is held in on this Mac: bfloat16, unless `ZEPHRA_DIT_DTYPE` says
/// otherwise.
///
/// Decided here, at the backend's edge, and handed to the pipeline: the kit reads no
/// environment variable and asks no device. As with LTX-2.5 there is no M5 gate; the mlx-swift
/// split-K bug klein works around is specific to one matmul shape, and `ZEPHRA_DIT_DTYPE=f32`
/// is the bisection lever if an M5 ever shows the symptom here.
public enum WanActivationPrecision {
    /// The dtype for the next load.
    public static func resolve(environment: InferenceEnvironment) -> DType {
        environment.ditFloat32 == true ? .float32 : .bfloat16
    }
}
