import Foundation
import Testing

@testable import Zephra

/// The line under Settings > General's update toggle: what each outcome says, and how a stored
/// stamp reads back.
@Suite("The last update check's caption")
struct UpdateCheckNoteTests {
    @Test("each outcome finishes the sentence in its own words")
    func eachOutcomeHasItsWords() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateCheckNote(date: date, outcome: .upToDate).tail == ": up to date.")
        #expect(
            UpdateCheckNote(date: date, outcome: .found).tail
                == ": a newer version is available.")
        #expect(
            UpdateCheckNote(date: date, outcome: .failed).tail == ": the check did not finish.")
    }

    @Test("a stored stamp reads back as the check it recorded")
    func aStampReadsBack() {
        let note = UpdateCheckNote.stored(seconds: 1_800_000_000, outcome: "upToDate")
        #expect(
            note
                == UpdateCheckNote(
                    date: Date(timeIntervalSince1970: 1_800_000_000), outcome: .upToDate))
    }

    @Test("a Mac that never checked, or a word this build cannot read, is not checked yet")
    func nothingReadableIsNotCheckedYet() {
        #expect(UpdateCheckNote.stored(seconds: nil, outcome: nil) == nil)
        #expect(UpdateCheckNote.stored(seconds: 1_800_000_000, outcome: nil) == nil)
        #expect(UpdateCheckNote.stored(seconds: nil, outcome: "found") == nil)
        #expect(UpdateCheckNote.stored(seconds: 1_800_000_000, outcome: "sideways") == nil)
        #expect(UpdateCheckNote.notChecked == "Not checked yet.")
    }

    @Test("the outcome words are the ones the preferences keep")
    func theStoredWordsAreStable() {
        #expect(UpdateCheckNote.Outcome.upToDate.rawValue == "upToDate")
        #expect(UpdateCheckNote.Outcome.found.rawValue == "found")
        #expect(UpdateCheckNote.Outcome.failed.rawValue == "failed")
    }
}
