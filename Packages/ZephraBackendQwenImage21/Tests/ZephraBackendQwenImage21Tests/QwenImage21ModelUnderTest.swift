import Foundation
import ZephraCore

/// The descriptor these suites judge the backend against.
///
/// Written here rather than taken from `ModelCatalog`, because the catalog entry is a later
/// step's and this package must compile and pass before it lands. The numbers that matter are
/// the two the pipeline refuses anything else on — a 32-pixel size alignment and a step count
/// inside the schedule's range — and they are the kit's own
/// (`QwenImage21Configuration.sizeAlignment`). When the entry arrives, this becomes the place
/// the two are checked against each other.
enum QwenImage21ModelUnderTest {
    /// What the interface may ask for: 2.1 takes reference pictures and a negative prompt, and
    /// is sampled at `true_cfg_scale` 1 unless somebody raises it.
    static let capabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [ImageSize(width: 1024, height: 1024)],
        sizeBounds: 256...1536,
        defaultSize: ImageSize(width: 1024, height: 1024),
        stepBounds: 8...50,
        defaultSteps: 40,
        guidanceBounds: 1...5,
        defaultGuidance: 1,
        supportsNegativePrompt: true,
        supportsSeed: true,
        supportsReferenceImage: true
    )

    /// A 2.1-shaped model from a repository that does not exist, so no cache can answer for it.
    static func hub(builtBytes: Int64 = 4, downloadBytes: Int64 = 16) -> ModelDescriptor {
        ModelDescriptor(
            id: "qwen-image-2.1-availability-test", displayName: "Qwen-Image 2.1",
            variantName: "4-bit", backend: .qwenImage21,
            source: .huggingFace(
                repoID: "nobody/no-such-model", revision: "main", filePatterns: ["*"]),
            quantization: .int4, downloadBytes: downloadBytes, residentBytes: 1, peakBytes: 2,
            tiledPeakBytes: 2, maxPromptTokens: 1024, capabilities: capabilities,
            builtBytes: builtBytes)
    }

    /// The same model packed into a directory of its own on this Mac.
    static func local(_ directory: URL) -> ModelDescriptor {
        ModelDescriptor(
            id: "qwen-image-2.1-test", displayName: "Qwen-Image 2.1", variantName: "4-bit",
            backend: .qwenImage21, source: .localDirectory(directory), quantization: .int4,
            downloadBytes: 0, residentBytes: 1, peakBytes: 2, tiledPeakBytes: 2,
            maxPromptTokens: 1024, capabilities: capabilities)
    }
}
