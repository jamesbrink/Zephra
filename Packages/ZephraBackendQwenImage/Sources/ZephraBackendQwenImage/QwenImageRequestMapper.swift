import Foundation
import QwenImage
import ZephraCore

/// Turns Zephra's settings into a pipeline request.
enum QwenImageRequestMapper {
    /// The request for `settings`, clamped to what the model actually accepts.
    ///
    /// A reference image survives that clamp only on a model that can start from one, and it is
    /// decoded here rather than inside the pipeline, so a picture that will not open fails
    /// before the first denoising step. That is the only thing this can throw.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) throws -> QwenImageGenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return QwenImageGenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            steps: clamped.steps,
            seed: clamped.seed,
            maxPromptTokens: descriptor.maxPromptTokens,
            referenceImage: try clamped.referenceImage.map {
                try ReferenceImageDecoding.cgImage(from: $0)
            },
            // No picture, no distance from one: the strength a settings value happens to be
            // carrying is not a request to enter the loop late when nothing was handed in.
            referenceStrength: clamped.referenceImage == nil ? 1 : clamped.referenceStrength
        )
    }
}
