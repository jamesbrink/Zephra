import Flux2
import ZephraCore

/// Translates the engine's settings into the pipeline's request.
enum Flux2RequestMapper {
    /// The request for `settings` on `descriptor`, after the model's own limits are applied.
    ///
    /// Clamping first is the invariant: the reference picture is dropped here for a model that
    /// cannot read one, and the size is aligned to the latent grid, so what the pipeline sees is
    /// always something it can run.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) -> Flux2GenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return Flux2GenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            steps: clamped.steps,
            seed: clamped.seed,
            maxPromptTokens: descriptor.maxPromptTokens,
            referenceImage: clamped.referenceImage
        )
    }
}
