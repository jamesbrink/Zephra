import Foundation
import QwenImage
import ZephraCore

/// Turns Zephra's settings into a pipeline request.
enum QwenImageRequestMapper {
    /// The request for `settings`, clamped to what the model actually accepts.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor
    ) -> QwenImageGenerationRequest {
        let clamped = descriptor.capabilities.clamp(settings)
        return QwenImageGenerationRequest(
            prompt: clamped.prompt,
            width: clamped.size.width,
            height: clamped.size.height,
            steps: clamped.steps,
            seed: clamped.seed,
            maxPromptTokens: descriptor.maxPromptTokens
        )
    }
}
