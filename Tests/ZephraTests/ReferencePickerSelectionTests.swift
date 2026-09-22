import Testing
import ZephraEngine

@testable import Zephra

/// Picking several pictures in the reference sheet.
///
/// The rules are `LibraryCursor`'s, the same ones the library grid walks by; what is pinned
/// here is the cap a model's own count puts on them, the order the tiles will end up in, and
/// the one-picture model behaving exactly as it always has.
@MainActor
@Suite("Picking reference pictures in the sheet")
struct ReferencePickerSelectionTests {
    private let matches = LibraryIndex.preview(count: 6).sections.flatMap(\.items)

    @Test("a plain click picks one and replaces whatever was picked before")
    func aPlainClickPicksOne() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.click(matches[3].id, in: matches, modifiers: [])
        #expect(selection.ids == [matches[3].id])
        #expect(selection.picked.map(\.id) == [matches[3].id])
    }

    @Test("a command-click adds one and a second takes it away again")
    func commandClickToggles() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.click(matches[2].id, in: matches, modifiers: .command)
        #expect(selection.count == 2)
        selection.click(matches[2].id, in: matches, modifiers: .command)
        #expect(selection.ids == [matches[0].id])
    }

    @Test("a shift-click takes the run between the anchor and it, in the grid's order")
    func shiftClickTakesTheRun() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[1].id, in: matches, modifiers: [])
        selection.click(matches[4].id, in: matches, modifiers: .shift)
        #expect(selection.count == 4)
        #expect(selection.picked.map(\.id) == matches[1...4].map(\.id))
    }

    @Test("a model that reads one picture ignores the modifiers entirely")
    func onePictureIgnoresModifiers() {
        let selection = ReferencePickerSelection()
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.click(matches[2].id, in: matches, modifiers: .command)
        #expect(selection.ids == [matches[2].id])
        selection.click(matches[5].id, in: matches, modifiers: .shift)
        #expect(selection.ids == [matches[5].id])
    }

    @Test("a run past the model's count keeps the pictures nearest the anchor")
    func theCapKeepsWhatIsNearestTheAnchor() {
        let selection = ReferencePickerSelection(limit: 3)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.click(matches[5].id, in: matches, modifiers: .shift)
        #expect(selection.count == 3)
        #expect(selection.picked.map(\.id) == matches[0...2].map(\.id))
        #expect(selection.anchor == matches[0].id)
    }

    @Test("a shift-arrow grows the run and shrinks it back the way it grew")
    func shiftArrowGrowsAndShrinks() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.move(.right, in: matches, extending: true)
        selection.move(.right, in: matches, extending: true)
        #expect(selection.count == 3)
        selection.move(.left, in: matches, extending: true)
        #expect(selection.count == 2)
    }

    @Test("a plain arrow moves the one pick rather than growing anything")
    func aPlainArrowMovesOne() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.move(.right, in: matches)
        #expect(selection.ids == [matches[1].id])
    }

    @Test("a pick that leaves the grid is dropped rather than used")
    func aPickThatLeavesTheGridIsDropped() {
        let selection = ReferencePickerSelection(limit: 10)
        selection.click(matches[0].id, in: matches, modifiers: [])
        selection.click(matches[4].id, in: matches, modifiers: .command)
        selection.prune(to: Array(matches[0...1]))
        #expect(selection.ids == [matches[0].id])
        #expect(selection.picked.map(\.id) == [matches[0].id])
    }

    @Test("the Use button says the number once there is more than one")
    func theUseButtonSaysTheNumber() {
        let selection = ReferencePickerSelection(limit: 10)
        #expect(selection.useTitle == "Use")
        selection.click(matches[0].id, in: matches, modifiers: [])
        #expect(selection.useTitle == "Use")
        selection.click(matches[2].id, in: matches, modifiers: .shift)
        #expect(selection.useTitle == "Use 3 as References")
    }

    @Test("a limit under one is still one picture, never none")
    func theLimitIsNeverZero() {
        let selection = ReferencePickerSelection(limit: 0)
        #expect(selection.limit == 1)
        #expect(!selection.allowsSeveral)
    }
}
