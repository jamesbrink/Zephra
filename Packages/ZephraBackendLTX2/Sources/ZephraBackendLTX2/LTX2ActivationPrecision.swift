import MLX
import ZephraCore

/// What LTX-2.5's stream is held in on this Mac: bfloat16, unless `ZEPHRA_DIT_DTYPE` says
/// otherwise.
///
/// Decided here, at the backend's edge, and handed to the pipeline: the kit reads no
/// environment variable and asks no device. Unlike klein there is no M5 gate. The mlx-swift
/// split-K bug that gate works around is specific to one matmul shape in klein's single-stream
/// block, and nothing says LTX-2.5's shapes reach it; running a 22B model in float32 on
/// suspicion would triple its step time for everyone on an M5. `ZEPHRA_DIT_DTYPE=f32` is the
/// bisection lever if an M5 ever shows the symptom (`ROADMAP.md`).
public enum LTX2ActivationPrecision {
    /// The dtype for the next load.
    public static func resolve(environment: InferenceEnvironment) -> DType {
        environment.ditFloat32 == true ? .float32 : .bfloat16
    }
}
