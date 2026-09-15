import Foundation
import Testing
import ZephraCore

@testable import ZephraMobile

@MainActor
@Suite("Reusing a generated image")
struct PromptDraftReuseTests {
    @Test("Recorded settings replace the draft and survive the first host snapshot")
    func restoresProvenance() throws {
        var entry = LibraryFixtures.template
        entry.record?.prompt = "A new prompt"
        entry.record?.negativePrompt = "blur"
        entry.record?.seed = 42
        entry.record?.steps = 17
        entry.record?.guidance = 3.5
        let record = try #require(entry.record)
        let draft = PromptDraft()
        draft.settings.prompt = "Unrelated draft"
        draft.reference = Data([1, 2, 3])
        draft.settings.referenceOrigin = "old.png"
        draft.count = 8
        #expect(draft.reuse(CachedEntry(entry)))
        draft.adopt(MobilePreview.snapshot())
        #expect(draft.settings == record.settings())
        #expect(draft.modelID == record.modelID)
        #expect(draft.reference == nil)
        #expect(draft.referenceSize == nil)
        #expect(draft.settings.referenceOrigin == nil)
        #expect(draft.count == 1)
    }

    @Test("An imported image without provenance leaves the draft intact")
    func missingRecord() {
        var entry = LibraryFixtures.template
        entry.record = nil
        let draft = PromptDraft()
        draft.settings.prompt = "Keep this"
        let before = draft.settings
        #expect(!draft.reuse(CachedEntry(entry)))
        #expect(draft.settings == before)
    }

    @Test("Video settings retain their recorded duration")
    func video() throws {
        let entry = LibraryFixtures.clip
        let record = try #require(entry.record)
        let draft = PromptDraft()
        #expect(draft.reuse(CachedEntry(entry)))
        #expect(draft.settings.frames == record.frameCount)
        #expect(draft.settings.continuation == nil)
    }
}
