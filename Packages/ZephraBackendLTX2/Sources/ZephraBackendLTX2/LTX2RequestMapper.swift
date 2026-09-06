import LTX2
import ZephraCore

/// Translates the engine's settings into the pipeline's request.
enum LTX2RequestMapper {
    /// The request for `settings` on `descriptor`, after the model's own limits are applied.
    ///
    /// Clamping first is the invariant: the size is aligned to the 32-pixel latent cell and the
    /// frame count to the `1 + 8k` ladder, so what the pipeline sees is always something it can
    /// run. Steps are not carried: the distilled schedule fixes them.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) -> LTX2GenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return LTX2GenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            frames: clamped.frames,
            frameRate: descriptor.capabilities.frameRate,
            seed: clamped.seed,
            maxPromptTokens: descriptor.maxPromptTokens
        )
    }
}
