import MLX
import ZephraMLX

/// What the denoising loop asks of the model at each step: the velocity for these latents.
///
/// `QwenImageTransformer` is the one that matters; the protocol exists so the loop's own
/// arithmetic — where it enters with a reference, what it reports, what it hands a preview,
/// when it stops — can be pinned by `DenoiseLoopTests` through a stub that answers in a
/// microsecond, rather than through sixty blocks of random weights.
protocol QwenImageVelocityModel {
    /// Predicts the flow for one step; see `QwenImageTransformer.callAsFunction`.
    func callAsFunction(
        latents: MLXArray,
        text: MLXArray,
        timestep: MLXArray,
        frequencies: (image: RotaryFrequencies, text: RotaryFrequencies)
    ) throws -> MLXArray
}

extension QwenImageTransformer: QwenImageVelocityModel {}
