import Testing
import ZephraCore

@testable import ZephraMobile

/// Guidance above 1 spends a second forward classifier-free guidance needs a negative prompt to
/// use; with nothing to avoid, that forward is paid for and changes nothing.
@Suite("Guidance above 1 says so when there is nothing to avoid")
struct GuidanceNoteTests {
    private func capabilities(supportsNegativePrompt: Bool, adjustsGuidance: Bool = true)
        -> ModelCapabilities
    {
        ModelCapabilities(
            sizeAlignment: 64,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 256...2048,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...20, defaultSteps: 9,
            guidanceBounds: adjustsGuidance ? 0...8 : 0...0, defaultGuidance: 1,
            supportsNegativePrompt: supportsNegativePrompt, supportsSeed: true,
            supportsReferenceImage: false,
            referenceStrengthBounds: 1...1, defaultReferenceStrength: 1)
    }

    @Test("Guidance over 1 with an empty negative prompt gets the note")
    func guidanceWithNothingToAvoid() {
        let note = GuidanceNote.text(
            guidance: 2, negativePrompt: nil, capabilities: capabilities(supportsNegativePrompt: true))
        #expect(note == "Guidance needs something to avoid.")
    }

    @Test("A negative prompt clears the note")
    func aNegativePromptClearsIt() {
        let note = GuidanceNote.text(
            guidance: 2, negativePrompt: "blurry",
            capabilities: capabilities(supportsNegativePrompt: true))
        #expect(note == nil)
    }

    @Test("Guidance at 1 says nothing, whatever the negative prompt")
    func guidanceAtOneIsSilent() {
        let note = GuidanceNote.text(
            guidance: 1, negativePrompt: nil, capabilities: capabilities(supportsNegativePrompt: true))
        #expect(note == nil)
    }

    @Test("A model with no negative prompt at all never shows it")
    func aModelWithoutNegativePromptStaysSilent() {
        let note = GuidanceNote.text(
            guidance: 2, negativePrompt: nil,
            capabilities: capabilities(supportsNegativePrompt: false))
        #expect(note == nil)
    }

    @Test("A distilled model with fixed guidance never shows it")
    func aFixedGuidanceModelStaysSilent() {
        let note = GuidanceNote.text(
            guidance: 2, negativePrompt: nil,
            capabilities: capabilities(supportsNegativePrompt: true, adjustsGuidance: false))
        #expect(note == nil)
    }
}
