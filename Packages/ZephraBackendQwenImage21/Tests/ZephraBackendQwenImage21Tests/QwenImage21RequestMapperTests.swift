import Foundation
import Testing
import ZephraCore

@testable import ZephraBackendQwenImage21

@Suite("Settings become a 2.1 request only after the model's limits are applied")
struct QwenImage21RequestMapperTests {
    private let descriptor = QwenImage21ModelUnderTest.hub()

    @Test("size is aligned and bounded, steps are bounded, and the reference rides along")
    func clampsAndCarries() {
        let picture = Data([1, 2, 3])
        let settings = GenerationSettings(
            prompt: "a red door", size: ImageSize(width: 1030, height: 2000), steps: 90,
            guidance: 1, seed: 7, referenceImage: picture)
        let request = QwenImage21RequestMapper.request(for: settings, descriptor: descriptor)

        #expect(request.width == 1024)
        #expect(request.height == 1536)
        #expect(request.steps == 50)
        #expect(request.seed == 7)
        #expect(request.references == [picture])
    }

    @Test("a model that cannot read a reference drops it before the request is built")
    func dropsReferenceWhereUnsupported() {
        let settings = GenerationSettings(
            prompt: "x", size: ImageSize(width: 1024, height: 1024), steps: 40, guidance: 1,
            seed: 1, referenceImage: Data([9]))
        let request = QwenImage21RequestMapper.request(
            for: settings, descriptor: Self.referenceless)

        #expect(request.references.isEmpty)
    }

    @Test("the negative prompt rides only above guidance 1, which is the only place it is read")
    func negativePromptFollowsGuidance() {
        let settings = GenerationSettings(
            prompt: "a red door", negativePrompt: "blurry",
            size: ImageSize(width: 1024, height: 1024), steps: 40, guidance: 1, seed: 1)
        var raised = settings
        raised.guidance = 4

        let plain = QwenImage21RequestMapper.request(for: settings, descriptor: descriptor)
        let guided = QwenImage21RequestMapper.request(for: raised, descriptor: descriptor)

        #expect(plain.negativePrompt.isEmpty)
        #expect(!plain.usesGuidance)
        #expect(guided.guidance == 4)
        #expect(guided.negativePrompt == "blurry")
        #expect(guided.usesGuidance)
    }

    @Test("the engine's tile is halved for this autoencoder's sixteen-pixel cell")
    func tileIsHalved() {
        #expect(QwenImage21RequestMapper.vaeTile(from: 64) == 32)
        #expect(QwenImage21RequestMapper.vaeTile(from: 128) == 64)
        // Off means off: the exact, untiled decode, not a tile of the smallest size.
        #expect(QwenImage21RequestMapper.vaeTile(from: nil) == nil)
    }

    @Test("a tile too small to approximate faithfully is raised to the floor, never passed on")
    func tileHasAFloor() {
        // Halving 16 would give 8, which measured 26 dB against the untiled decode.
        #expect(QwenImage21RequestMapper.vaeTile(from: 16) == 12)
        #expect(QwenImage21RequestMapper.vaeTile(from: 8) == 12)
        #expect(QwenImage21RequestMapper.vaeTile(from: 24) == 12)
        #expect(QwenImage21RequestMapper.vaeTile(from: 32) == 16)
    }

    /// A stand-in for a model with no way to read a picture, built rather than borrowed: every
    /// model Zephra ships can take a reference, so borrowing one would stop testing the drop
    /// the day the catalog changed its mind.
    private static let referenceless: ModelDescriptor = {
        let base = QwenImage21ModelUnderTest.capabilities
        let capabilities = ModelCapabilities(
            sizeAlignment: base.sizeAlignment,
            sizePresets: base.sizePresets,
            sizeBounds: base.sizeBounds,
            defaultSize: base.defaultSize,
            stepBounds: base.stepBounds,
            defaultSteps: base.defaultSteps,
            guidanceBounds: base.guidanceBounds,
            defaultGuidance: base.defaultGuidance,
            supportsNegativePrompt: base.supportsNegativePrompt,
            supportsSeed: base.supportsSeed,
            supportsReferenceImage: false
        )
        let hub = QwenImage21ModelUnderTest.hub()
        return ModelDescriptor(
            id: "text-to-image-only", displayName: "Text to image only", variantName: nil,
            backend: hub.backend, source: hub.source, quantization: hub.quantization,
            downloadBytes: hub.downloadBytes, residentBytes: hub.residentBytes,
            peakBytes: hub.peakBytes, tiledPeakBytes: hub.tiledPeakBytes,
            maxPromptTokens: hub.maxPromptTokens, capabilities: capabilities)
    }()
}
