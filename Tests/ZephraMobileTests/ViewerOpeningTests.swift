import Foundation
import Testing

@testable import ZephraMobile

/// The viewer zooms out of the cell it opened from and back into the cell of the picture it
/// is on when it closes, under a source id the system fixed at presentation. Which cell
/// answers to that id is one rule, and this is it.
@Suite("Which cell the viewer zooms back into")
struct ViewerOpeningTests {
    private let entries = MobilePreview.library().map(CachedEntry.init)

    @Test("An opening is identified by the picture it opened on, and paging keeps that id")
    func identityIsTheOpenedPicture() {
        var opening = ViewerOpening(opened: entries[0])
        #expect(opening.id == entries[0].fileName)
        #expect(opening.shown == entries[0].fileName)
        opening.shown = entries[2].fileName
        #expect(opening.id == entries[0].fileName)
    }

    @Test("Before paging, the opened cell answers to its own name and no other cell answers")
    func onlyTheOpenedCellAnswersAtFirst() {
        let opening = ViewerOpening(opened: entries[0])
        #expect(opening.sourceID(forCell: entries[0].fileName) == entries[0].fileName)
        #expect(opening.sourceID(forCell: entries[1].fileName) == nil)
        #expect(opening.sourceID(forCell: entries[2].fileName) == nil)
    }

    @Test("After paging, the shown picture's cell answers to the opened one's name")
    func shownCellTakesTheOpenedName() {
        var opening = ViewerOpening(opened: entries[0])
        opening.shown = entries[2].fileName
        #expect(opening.sourceID(forCell: entries[2].fileName) == entries[0].fileName)
    }

    @Test("Once paged away from, the opened cell answers to nothing, so one cell holds the id")
    func openedCellStepsAside() {
        var opening = ViewerOpening(opened: entries[0])
        opening.shown = entries[2].fileName
        #expect(opening.sourceID(forCell: entries[0].fileName) == nil)
        #expect(opening.sourceID(forCell: entries[1].fileName) == nil)
        let claimed = entries.compactMap { opening.sourceID(forCell: $0.fileName) }
        #expect(claimed == [entries[0].fileName])
    }

    @Test("Paging back to the opened picture hands the id back to its cell")
    func pagingBackRestoresTheOpenedCell() {
        var opening = ViewerOpening(opened: entries[0])
        opening.shown = entries[1].fileName
        opening.shown = entries[0].fileName
        #expect(opening.sourceID(forCell: entries[0].fileName) == entries[0].fileName)
        #expect(opening.sourceID(forCell: entries[1].fileName) == nil)
    }
}
