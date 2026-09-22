import Foundation
import ZephraCore

/// An invented model, used only by `#Preview`s, so the controls a model with guidance and a
/// negative prompt would show can be seen without one existing. Nothing ships against it and it
/// is never offered in the picker: the picker lists `ModelCatalog.all`.
enum PreviewModel {
    /// A model that reads a negative prompt and responds to guidance, unlike Z-Image Turbo.
    static let guided = ModelDescriptor(
        id: "preview-guided",
        displayName: "Preview Model",
        variantName: "guided",
        backend: "preview",
        source: .localDirectory(URL(filePath: "/tmp/preview-model")),
        quantization: .bf16,
        downloadBytes: 0,
        residentBytes: 1_000_000_000,
        peakBytes: 3_000_000_000,
        tiledPeakBytes: 2_000_000_000,
        maxPromptTokens: 256,
        capabilities: ModelCapabilities(
            sizeAlignment: 64,
            sizePresets: [
                ImageSize(width: 1024, height: 1024),
                ImageSize(width: 768, height: 1024),
            ],
            sizeBounds: 512...1536,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...50,
            defaultSteps: 20,
            guidanceBounds: 1...12,
            defaultGuidance: 6,
            supportsNegativePrompt: true,
            supportsSeed: true
        )
    )

    /// A model that makes clips from a picture, the way LTX-2.5 does, for the `clip` screenshot
    /// build.
    static let video = ModelDescriptor(
        id: "preview-video",
        displayName: "Preview Model",
        variantName: "video",
        backend: "preview",
        source: .localDirectory(URL(filePath: "/tmp/preview-model")),
        quantization: .int4,
        downloadBytes: 0,
        residentBytes: 8_000_000_000,
        peakBytes: 20_000_000_000,
        tiledPeakBytes: 20_000_000_000,
        maxPromptTokens: 1024,
        capabilities: ModelCapabilities(
            sizeAlignment: 32,
            sizePresets: [
                ImageSize(width: 768, height: 512),
                ImageSize(width: 512, height: 768),
            ],
            sizeBounds: 256...1024,
            defaultSize: ImageSize(width: 768, height: 512),
            stepBounds: 8...8,
            defaultSteps: 8,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true,
            referenceStrengthBounds: 0.0...0.9,
            defaultReferenceStrength: 0,
            frameBounds: 9...121,
            defaultFrames: 49,
            frameAlignment: 8,
            frameRate: 24
        )
    )

    /// A model that edits pictures handed in beside the prompt, the way FLUX.2 klein does, with
    /// none of the controls it does not read.
    ///
    /// It reads up to ten of them, so the `editing` and `picker` screenshot builds photograph
    /// the strip rather than the single well. `video` beside it stays at one, which is what
    /// keeps the single well photographable through `clip` and keeps the two shapes both
    /// covered by a preview state.
    static let editing = ModelDescriptor(
        id: "preview-editing",
        displayName: "Preview Model",
        variantName: "editing",
        backend: "preview",
        source: .localDirectory(URL(filePath: "/tmp/preview-model")),
        quantization: .int4,
        downloadBytes: 0,
        residentBytes: 5_000_000_000,
        peakBytes: 10_000_000_000,
        tiledPeakBytes: 7_000_000_000,
        maxPromptTokens: 512,
        capabilities: ModelCapabilities(
            sizeAlignment: 16,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...1536,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...8,
            defaultSteps: 4,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true,
            referenceImageCount: 1...10,
            referenceStrengthBounds: 0.1...0.9,
            defaultReferenceStrength: 0.6
        )
    )
}
