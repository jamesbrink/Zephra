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
        #expect(capabilities.supportsReferenceImage, "Z-Image starts from a noised copy")
        #expect(capabilities.clamp(settings).referenceImage == picture)
        #expect(withoutReferences.clamp(settings).referenceImage == nil)
    }

    @Test("clamp holds the reference strength inside the model's bounds")
    func clampsReferenceStrength() {
        #expect(capabilities.referenceStrengthBounds == 0.1...0.9)
        var settings = makeSettings()
        settings.referenceStrength = 4
        #expect(capabilities.clamp(settings).referenceStrength == 0.9)
        settings.referenceStrength = -1
        #expect(capabilities.clamp(settings).referenceStrength == 0.1)
        settings.referenceStrength = 0.45
        #expect(capabilities.clamp(settings).referenceStrength == 0.45, "already inside")
    }

    @Test("a model that conditions on the picture directly pins the strength at 1")
    func degenerateBoundsMeanStrengthDoesNotApply() {
        // What FLUX.2 klein declares: it attends to the reference as extra tokens and still
        // walks the whole schedule, so there is no distance to travel and no slider to show.
        // Expressed the way `guidanceBounds: 0...0` expresses "guidance does not apply".
        let klein = ModelCatalog.flux2Klein4bit.capabilities
        #expect(klein.supportsReferenceImage)
        #expect(klein.referenceStrengthBounds == 1...1)
        var settings = makeSettings()
        settings.referenceStrength = 0.3
        #expect(klein.clamp(settings).referenceStrength == 1)
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

    /// The same capabilities with references turned off, so the drop is exercised rather than
    /// assumed: every model the catalog ships can read one.
    private var withoutReferences: ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: capabilities.sizeAlignment,
            sizePresets: capabilities.sizePresets,
            sizeBounds: capabilities.sizeBounds,
            defaultSize: capabilities.defaultSize,
            stepBounds: capabilities.stepBounds,
            defaultSteps: capabilities.defaultSteps,
            guidanceBounds: capabilities.guidanceBounds,
            defaultGuidance: capabilities.defaultGuidance,
            supportsNegativePrompt: capabilities.supportsNegativePrompt,
            supportsSeed: capabilities.supportsSeed,
            supportsReferenceImage: false
        )
    }
}

@Suite("ModelCapabilities says which sliders are real")
struct ModelCapabilityAdjustabilityTests {
    @Test("a single legal guidance or strength value means no slider")
    func degenerateBoundsHideTheSlider() {
        let turbo = ModelCatalog.zImageTurbo8bit.capabilities
        #expect(!turbo.adjustsGuidance, "Z-Image Turbo is distilled to one guidance")
        #expect(turbo.adjustsReferenceStrength, "and starts from a noised copy of a picture")
        let klein = ModelCatalog.flux2Klein4bit.capabilities
        #expect(!klein.adjustsGuidance)
        #expect(!klein.adjustsReferenceStrength, "klein conditions on the picture instead")
    }
}
