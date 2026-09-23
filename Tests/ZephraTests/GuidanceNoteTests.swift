import Foundation
import Testing
import ZephraCore

@testable import Zephra

/// What the guidance control says under itself when guidance cannot do anything.
@Suite("The note under the guidance control")
struct GuidanceNoteTests {
    private func capabilities(guidance: ClosedRange<Double> = 1...8, negative: Bool = true)
        -> ModelCapabilities
    {
        ModelCapabilities(
            sizeAlignment: 32,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...2048,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 8...50,
            defaultSteps: 40,
            guidanceBounds: guidance,
            defaultGuidance: guidance.lowerBound,
            supportsNegativePrompt: negative,
            supportsSeed: true)
    }

    private func settings(guidance: Double, negative: String?) -> GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse", negativePrompt: negative,
            size: ImageSize(width: 1024, height: 1024), steps: 40, guidance: guidance, seed: 1)
    }

    @Test("guidance above 1 with an empty negative prompt asks for something to avoid")
    func asksForANegativePrompt() {
        let capabilities = capabilities()
        #expect(GuidanceNote.text(for: settings(guidance: 4, negative: nil), capabilities: capabilities)
            == "Guidance needs something to avoid.")
        #expect(GuidanceNote.text(for: settings(guidance: 4, negative: "  \n"), capabilities: capabilities)
            == GuidanceNote.needsNegativePrompt)
    }

    @Test("guidance at 1, or a negative prompt with something in it, says nothing")
    func silentWhenGuidanceCanWork() {
        let capabilities = capabilities()
        #expect(GuidanceNote.text(for: settings(guidance: 1, negative: nil), capabilities: capabilities) == nil)
        #expect(GuidanceNote.text(for: settings(guidance: 4, negative: "blur"), capabilities: capabilities) == nil)
    }

    @Test("a model without a negative prompt or without a guidance choice says nothing")
    func silentWhereItDoesNotApply() {
        let high = settings(guidance: 4, negative: nil)
        #expect(GuidanceNote.text(for: high, capabilities: capabilities(negative: false)) == nil)
        #expect(GuidanceNote.text(for: high, capabilities: capabilities(guidance: 0...0)) == nil)
    }
}
