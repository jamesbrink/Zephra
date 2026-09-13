import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol

@testable import ZephraMobile

/// What the model menu offers, which is the Mac's two answers and nothing of the phone's own.
@Suite("A model row is drawn from what the Mac said about it")
struct ModelChoosingTests {
    /// One summary, selectable unless a test says otherwise.
    static func model(isSelectable: Bool = true, note: String? = nil) -> ModelSummary {
        ModelSummary(
            id: "a-model", displayName: "A Model", variantName: "4-bit", familyID: "z-image",
            capabilities: CapabilitiesSummary(ModelCatalog.default.capabilities),
            isSelectable: isSelectable, memoryNote: note)
    }

    @Test("a model this Mac cannot hold is not pressable, and says what it would need")
    func aModelTheMacCannotHoldIsGreyed() {
        let model = Self.model(isSelectable: false, note: "Needs 23 GB")
        let downloaded = AvailabilityDTO(.available)

        #expect(!model.isChoosable(availability: downloaded))
        #expect(model.note(availability: downloaded) == "Needs 23 GB")
    }

    @Test("a model that cannot be had at all says that first, before anything about memory")
    func anUnobtainableModelSaysSo() {
        let model = Self.model(isSelectable: false, note: "Needs 23 GB")
        let missing = AvailabilityDTO(.missing(reason: "Nothing to build it from."))

        #expect(!model.isChoosable(availability: missing))
        #expect(model.note(availability: missing) == missing.label)
    }

    @Test("a download says its size first, since the press is what starts it")
    func aDownloadSaysItsSizeFirst() {
        let model = Self.model(note: "Streams from disk")
        let download = AvailabilityDTO(.needsDownload(bytes: 4_000_000_000))

        #expect(model.isChoosable(availability: download))
        #expect(model.note(availability: download) == download.label)
    }

    @Test("a model already here that streams from disk says so, as the Mac's own row does")
    func aStreamedModelSaysHowItRuns() {
        let model = Self.model(note: "Streams from disk")
        let downloaded = AvailabilityDTO(.available)

        #expect(model.isChoosable(availability: downloaded))
        #expect(model.note(availability: downloaded) == "Streams from disk")
    }

    @Test("a model that simply runs keeps the availability line")
    func aFittingModelKeepsItsAvailability() {
        let model = Self.model()
        let downloaded = AvailabilityDTO(.available)

        #expect(model.isChoosable(availability: downloaded))
        #expect(model.note(availability: downloaded) == downloaded.label)
    }

    @Test("a model an older Mac listed, with no verdict at all, is still pressable")
    func anOlderMacsModelIsPressable() {
        let model = Self.model()

        #expect(model.isChoosable(availability: nil))
        #expect(model.note(availability: nil) == nil)
    }

    @Test("the frozen fixture holds one model this Mac cannot hold, so the greyed row is seen")
    func theFixtureHoldsAGreyedModel() throws {
        let snapshot = try #require(MobilePreview.snapshot())
        let greyed = try #require(snapshot.models.first { !$0.isSelectable })

        #expect(greyed.memoryNote == "Needs 23 GB")
        #expect(!greyed.isChoosable(availability: snapshot.availability[greyed.id]))
        #expect(snapshot.model.isSelectable, "the model in force is one the Mac runs")
    }
}
