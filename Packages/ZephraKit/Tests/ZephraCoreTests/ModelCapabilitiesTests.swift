import Foundation
import Testing

@testable import ZephraCore

@Suite("ModelCapabilities")
struct ModelCapabilitiesTests {
    private let capabilities = ModelCatalog.zImageTurbo8bit.capabilities

    @Test("clamp aligns the requested size")
    func clampAlignsSize() {
        let settings = makeSettings(size: ImageSize(width: 1020, height: 761))
        #expect(capabilities.clamp(settings).size == ImageSize(width: 1024, height: 768))
    }

    @Test("clamp pulls an oversized request back inside the bounds")
    func clampBoundsSize() {
        let settings = makeSettings(size: ImageSize(width: 4000, height: 100))
        let clamped = capabilities.clamp(settings).size
        #expect(clamped == ImageSize(width: 2048, height: 512))
    }

    @Test("clamp holds steps inside the supported range")
    func clampSteps() {
        #expect(capabilities.clamp(makeSettings(steps: 99)).steps == 20)
        #expect(capabilities.clamp(makeSettings(steps: 0)).steps == 1)
    }

    @Test("clamp holds guidance inside the supported range")
    func clampGuidance() {
        #expect(capabilities.clamp(makeSettings(guidance: 7.5)).guidance == 0)
        #expect(capabilities.clamp(makeSettings(guidance: -3)).guidance == 0)
    }

    @Test("clamp drops a negative prompt the model cannot use")
    func dropsNegativePrompt() {
        let settings = makeSettings(negativePrompt: "blurry")
        #expect(capabilities.clamp(settings).negativePrompt == nil)
    }

    @Test("clamp keeps a negative prompt when the model reads it")
    func keepsNegativePrompt() {
        let supporting = ModelCapabilities(
            sizeAlignment: capabilities.sizeAlignment,
            sizePresets: capabilities.sizePresets,
            sizeBounds: capabilities.sizeBounds,
            defaultSize: capabilities.defaultSize,
            stepBounds: capabilities.stepBounds,
            defaultSteps: capabilities.defaultSteps,
            guidanceBounds: 1...10,
            defaultGuidance: 3,
            supportsNegativePrompt: true,
            supportsSeed: true
        )
        let settings = makeSettings(negativePrompt: "blurry", guidance: 3)
        #expect(supporting.clamp(settings).negativePrompt == "blurry")
    }

    @Test("clamp drops a reference image the model cannot read, and keeps one where it can")
    func referenceImageFollowsTheCapability() {
        let picture = Data([0x89, 0x50, 0x4E, 0x47])
        let settings = makeSettings(referenceImage: picture)
        #expect(capabilities.clamp(settings).referenceImage == nil)
        let editing = ModelCapabilities(
            sizeAlignment: capabilities.sizeAlignment,
            sizePresets: capabilities.sizePresets,
            sizeBounds: capabilities.sizeBounds,
            defaultSize: capabilities.defaultSize,
            stepBounds: capabilities.stepBounds,
            defaultSteps: capabilities.defaultSteps,
            guidanceBounds: capabilities.guidanceBounds,
            defaultGuidance: capabilities.defaultGuidance,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true
        )
        #expect(editing.clamp(settings).referenceImage == picture)
    }

    private func makeSettings(
        referenceImage: Data? = nil,
        negativePrompt: String? = nil,
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        steps: Int = 9,
        guidance: Double = 0
    ) -> GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse",
            negativePrompt: negativePrompt,
            size: size,
            steps: steps,
            guidance: guidance,
            seed: 42,
            referenceImage: referenceImage
        )
    }
}
