import LTX2
import ZephraCore

/// Translates the engine's settings into the pipeline's request.
enum LTX2RequestMapper {
    /// The request for `settings` on `descriptor`, after the model's own limits are applied.
    ///
    /// Clamping first is the invariant: the size is aligned to the 32-pixel latent cell and the
    /// frame count to the `1 + 8k` ladder, so what the pipeline sees is always something it can
    /// run. Steps are not carried: the distilled schedule fixes them.
    ///
    /// A reference picture is decoded here rather than inside the pipeline, so a picture that
    /// will not open fails before the first denoising step. That is the only thing this throws.
    ///
    /// **The strength is inverted.** Everywhere else in Zephra it reads as "how much of the
    /// picture to throw away", on a model that starts from a noised copy of it. LTX-2.5 does
    /// not start from the picture; it holds it as the clip's first frame, and what the loop
    /// wants is how strongly to hold it. So 0, this model's default, becomes a conditioning
    /// strength of 1 and holds the frame exactly, and the catalog's upper bound of 0.9 becomes
    /// 0.1, barely held at all. There is no picture-less case to invert: a settings value with
    /// no picture attached is not a request to hold anything.
    ///
    /// Whether the clip is made in one stage or two is `LTX2StagePlan`'s answer for the size,
    /// under `environment`'s override.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor,
        environment: InferenceEnvironment = InferenceEnvironment()
    ) throws -> LTX2GenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return LTX2GenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            frames: clamped.frames,
            frameRate: descriptor.capabilities.frameRate,
            seed: clamped.seed,
            maxPromptTokens: descriptor.maxPromptTokens,
            firstFrame: try clamped.referenceImage.map {
                LTX2FirstFrame(
                    image: try ReferenceImageDecoding.cgImage(from: $0),
                    strength: Float(1 - clamped.referenceStrength))
            },
            twoStage: LTX2StagePlan.twoStage(
                width: clamped.size.width, height: clamped.size.height, environment: environment)
        )
    }
}
