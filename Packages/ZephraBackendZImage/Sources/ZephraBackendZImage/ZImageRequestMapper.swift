import Foundation
import ZephraCore
import ZImage

/// Builds a vendored-pipeline request from the app's settings, applying the model's own limits.
nonisolated enum ZImageRequestMapper {
    /// Translates settings into a request the pipeline will accept.
    ///
    /// Settings are put through `capabilities.clamp` first, which aligns the size to the
    /// model's 16-pixel grid, bounds the step count and guidance, and drops a negative prompt
    /// the model would ignore. `model` is always the resolved snapshot directory: the
    /// pipeline's own default points at the 33 GB bf16 repository, not the variant Zephra runs.
    ///
    /// A reference image survives that clamp only on a model that can start from one, and it is
    /// decoded here rather than inside the pipeline, so a picture that will not open fails
    /// before any weights are asked for. That is the only thing this can throw; everything else
    /// it does is arithmetic. The strength comes through clamped too, so what reaches the
    /// pipeline is always inside the bounds the descriptor advertises.
    static func request(
        for settings: GenerationSettings,
        descriptor: ModelDescriptor,
        snapshot: URL
    ) throws -> ZImageGenerationRequest {
        let capabilities = descriptor.capabilities
        let clamped = capabilities.clamp(settings)
        var request = ZImageGenerationRequest(
            prompt: clamped.prompt,
            negativePrompt: clamped.negativePrompt,
            width: clamped.size.width,
            height: clamped.size.height,
            steps: clamped.steps,
            guidanceScale: Float(clamped.guidance),
            seed: capabilities.supportsSeed ? clamped.seed : nil,
            outputPath: outputPath(for: descriptor),
            model: snapshot.path,
            maxSequenceLength: descriptor.maxPromptTokens
        )
        if let reference = clamped.referenceImage {
            request.referenceImage = try ReferenceImageDecoding.cgImage(from: reference)
            request.referenceStrength = Float(clamped.referenceStrength)
        }
        return request
    }

    /// A throwaway destination. `generateToMemory` never writes it, but the request requires
    /// one and the pipeline logs it, so it points somewhere plausible rather than at the
    /// working directory.
    private static func outputPath(for descriptor: ModelDescriptor) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "zephra-\(descriptor.id)-unused.png")
    }
}
