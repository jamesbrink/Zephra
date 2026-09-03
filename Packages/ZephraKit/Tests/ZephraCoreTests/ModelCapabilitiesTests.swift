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

    @Test("clamp drops a reference the model cannot start from")
    func dropsUnsupportedReference() {
        let settings = makeSettings(reference: Self.reference)
        #expect(withoutReferences.clamp(settings).reference == nil)
    }

    @Test("clamp holds the reference strength inside the model's bounds")
    func clampsReferenceStrength() {
        #expect(capabilities.supportsReferenceImage)
        let strong = makeSettings(reference: Self.reference.withStrength(4))
        #expect(capabilities.clamp(strong).reference?.strength == 0.9)

        let weak = makeSettings(reference: Self.reference.withStrength(-1))
        #expect(capabilities.clamp(weak).reference?.strength == 0.1)
    }

    @Test("clamp leaves a reference already inside the bounds exactly as it is")
    func keepsAcceptableReference() {
        let settings = makeSettings(reference: Self.reference)
        #expect(capabilities.clamp(settings).reference == Self.reference)
    }

    private func makeSettings(
        negativePrompt: String? = nil,
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        steps: Int = 9,
        guidance: Double = 0,
        reference: ReferenceImage? = nil
    ) -> GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse",
            negativePrompt: negativePrompt,
            size: size,
            steps: steps,
            guidance: guidance,
            seed: 42,
            reference: reference
        )
    }

    /// The same capabilities with references turned off, so the drop is exercised rather than
    /// assumed: both shipped families support them.
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

    private static let reference = ReferenceImage(
        url: URL(fileURLWithPath: "/tmp/sources/harbour.png"), strength: 0.6
    )
}
