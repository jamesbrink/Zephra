import Foundation
import Testing
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraMobile

/// Several reference pictures, from the well to the Mac.
///
/// What every one of these pins is that the phone asks for what the Mac it is talking to would
/// have allowed. A strip sent to a Mac that reads one picture is a strip the Mac trims, and the
/// pictures it trims were paid for over a relay first; a strip past the budget is a refusal
/// somebody can read rather than pictures that quietly did not arrive.
@MainActor
@Suite("The phone's well holds several pictures and sends what the Mac reads")
struct ReferenceStripTests {
    /// A picture model reading `count` pictures, in the wire's own form.
    private func summary(count: ClosedRange<Int>) -> CapabilitiesSummary {
        CapabilitiesSummary(
            ModelCapabilities(
                sizeAlignment: 64, sizePresets: [ImageSize(width: 1024, height: 1024)],
                sizeBounds: 256...2048, defaultSize: ImageSize(width: 1024, height: 1024),
                stepBounds: 1...20, defaultSteps: 9, guidanceBounds: 0...0, defaultGuidance: 0,
                supportsNegativePrompt: false, supportsSeed: true, supportsReferenceImage: true,
                referenceImageCount: count,
                referenceStrengthBounds: 0.1...0.9, defaultReferenceStrength: 0.6))
    }

    private func picture(_ name: String, bytes: Int = 3) -> ReferencePicture {
        ReferencePicture(
            data: Data(repeating: UInt8(name.utf8.first ?? 0), count: bytes), origin: name,
            size: ImageSize(width: 800, height: 600))
    }

    @Test("A Mac whose summary never mentioned a count is sent the first picture and no others")
    func anOlderMacIsSentOnePicture() {
        let draft = PromptDraft()
        let several = summary(count: 1...10)
        draft.replaceReferences(
            [picture("a.png"), picture("b.png"), picture("c.png")],
            fitting: several.capabilities)
        #expect(draft.references.count == 3)

        // 1...1 is exactly what `CapabilitiesSummary`'s decoder answers for a Mac that has
        // never heard of the field, so this is that Mac.
        let older = summary(count: 1...1)
        #expect(draft.references(allowedBy: older).map(\.origin) == ["a.png"])
        let request = draft.request(clampedBy: older)
        #expect(request.settings.referenceImages.count == 1)
        #expect(request.settings.referenceOrigin == "a.png")

        // The same draft, against a Mac that reads them all.
        #expect(draft.references(allowedBy: several).count == 3)
        #expect(draft.request(clampedBy: several).settings.referenceImages.count == 3)
    }

    @Test("A strip past the byte budget keeps what fits and says what it could not take")
    func theBudgetRefusesInOneSentence() {
        let draft = PromptDraft()
        let nine = 9 << 20
        draft.replaceReferences(
            [picture("a.png", bytes: nine), picture("b.png", bytes: nine),
             picture("c.png", bytes: nine)],
            fitting: summary(count: 1...10).capabilities)
        // Three nine-mebibyte pictures are 27 MiB against `ReferenceLimits.maximumTotalBytes`.
        #expect(draft.references.map(\.origin) == ["a.png", "b.png"])
        #expect(draft.referenceNote == "Only 2 of 3 pictures fit as references.")
    }

    @Test("Use as Reference adds where there is room and replaces where there is none")
    func useAsReferenceFollowsD7() {
        let draft = PromptDraft()
        let three = summary(count: 1...3).capabilities
        draft.useAsReferences([picture("a.png")], fitting: three)
        draft.useAsReferences([picture("b.png")], fitting: three)
        #expect(draft.references.map(\.origin) == ["a.png", "b.png"])

        draft.useAsReferences([picture("c.png")], fitting: three)
        #expect(draft.references.count == 3, "the third fills the last place")
        #expect(draft.referenceNote == nil)

        // No room left, so "use this as the reference" can only mean starting afresh.
        draft.useAsReferences([picture("d.png")], fitting: three)
        #expect(draft.references.map(\.origin) == ["d.png"])
        #expect(draft.referenceNote == nil)
    }

    @Test("On a model that reads one picture, taking another is today's replacement")
    func onePictureModelStillReplaces() {
        let draft = PromptDraft()
        let one = summary(count: 1...1).capabilities
        draft.useAsReferences([picture("a.png")], fitting: one)
        draft.useAsReferences([picture("b.png")], fitting: one)
        #expect(draft.references.map(\.origin) == ["b.png"])
    }

    @Test("Taking a picture out and moving one keep the strip's own order")
    func theStripIsOrderedByChoice() {
        let draft = PromptDraft()
        let ten = summary(count: 1...10).capabilities
        draft.replaceReferences(
            [picture("a.png"), picture("b.png"), picture("c.png")], fitting: ten)
        draft.moveReferences(fromOffsets: [2], toOffset: 0)
        #expect(draft.references.map(\.origin) == ["c.png", "a.png", "b.png"])
        draft.removeReference(at: 1)
        #expect(draft.references.map(\.origin) == ["c.png", "b.png"])
        draft.removeReference(at: 9)
        #expect(draft.references.count == 2, "an index the strip has not got changes nothing")
    }

    @Test("One request names several pictures, and is spent once")
    func theIntentCarriesSeveralNames() {
        let intent = ReferenceIntent()
        intent.use(["a.png", "b.png", "c.png"])
        #expect(intent.fileNames == ["a.png", "b.png", "c.png"])
        #expect(intent.fileName == "a.png", "the first is what a single-picture reader means")
        #expect(!intent.canGenerate)

        #expect(intent.take() == ["a.png", "b.png", "c.png"])
        #expect(intent.take().isEmpty, "a second reader gets nothing")
    }
}
