import Foundation
import Testing
import ZephraCore

@testable import ZephraBackendFlux2

@Suite("Settings become a klein request only after the model's limits are applied")
struct Flux2RequestMapperTests {
    private let descriptor = ModelCatalog.flux2Klein4bit

    @Test("size is aligned and bounded, steps are bounded, and the reference rides along")
    func clampsAndCarries() {
        let picture = Data([1, 2, 3])
        let settings = GenerationSettings(
            prompt: "a red door", size: ImageSize(width: 1030, height: 2000), steps: 40,
            guidance: 3, seed: 7, referenceImage: picture)
        let request = Flux2RequestMapper.request(for: settings, descriptor: descriptor)
        #expect(request.width == 1024)
        #expect(request.height == 1536)
        #expect(request.steps == 8)
        #expect(request.seed == 7)
        #expect(request.maxPromptTokens == 512)
        #expect(request.referenceImage == picture)
    }

    @Test("a model that cannot read a reference drops it before the request is built")
    func dropsReferenceWhereUnsupported() {
        let settings = GenerationSettings(
            prompt: "x", size: ImageSize(width: 1024, height: 1024), steps: 4, guidance: 0,
            seed: 1, referenceImage: Data([9]))
        let request = Flux2RequestMapper.request(for: settings, descriptor: Self.referenceless)
        #expect(request.referenceImage == nil)
    }

    /// A stand-in for a model with no way to read a picture.
    ///
    /// Built rather than borrowed from the catalog: every model Zephra ships can now take a
    /// reference — klein by conditioning on it, Z-Image and Qwen-Image by starting from a
    /// noised copy — so borrowing one would stop testing the drop the day the catalog changed
    /// its mind, which is exactly what happened to the entry this used to name.
    private static let referenceless: ModelDescriptor = {
        let base = ModelCatalog.flux2Klein4bit
        let capabilities = ModelCapabilities(
            sizeAlignment: base.capabilities.sizeAlignment,
            sizePresets: base.capabilities.sizePresets,
            sizeBounds: base.capabilities.sizeBounds,
            defaultSize: base.capabilities.defaultSize,
            stepBounds: base.capabilities.stepBounds,
            defaultSteps: base.capabilities.defaultSteps,
            guidanceBounds: base.capabilities.guidanceBounds,
            defaultGuidance: base.capabilities.defaultGuidance,
            supportsNegativePrompt: base.capabilities.supportsNegativePrompt,
            supportsSeed: base.capabilities.supportsSeed,
            supportsReferenceImage: false
        )
        return ModelDescriptor(
            id: "text-to-image-only",
            displayName: "Text to image only",
            variantName: nil,
            backend: base.backend,
            source: base.source,
            quantization: base.quantization,
            downloadBytes: base.downloadBytes,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: capabilities
        )
    }()
}
