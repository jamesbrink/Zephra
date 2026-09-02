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
}
