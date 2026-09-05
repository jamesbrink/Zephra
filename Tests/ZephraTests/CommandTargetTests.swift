import Foundation
import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

@Suite("What the file commands in the menu bar are about")
struct CommandTargetTests {
    /// Six invented images over a few days, none of them on disk.
    private let sections = LibraryIndex.preview(count: 6).sections
    private let picture = PreviewImages.sample()

    private var firstItem: LibraryItem { sections[0].items[0] }

    @Test("the canvas pane with a picture on it is the picture")
    func canvasWithAPictureIsTheCanvas() {
        let target = CommandTarget.resolve(
            pane: .canvas, isShowingRun: false, current: picture, gridSelection: nil, sections: sections)
        #expect(target == .canvas(picture))
        #expect(target.count == 1)
    }

    @Test("the canvas pane while it follows a run is nothing: there is no file yet, only frames")
    func canvasFollowingARunIsNone() {
        let target = CommandTarget.resolve(
            pane: .canvas, isShowingRun: true, current: picture, gridSelection: nil, sections: sections)
        #expect(target == .none)
        #expect(target.isEmpty)
    }

    @Test("the library pane with no grid focus is nothing, even with a picture behind it on the canvas")
    func libraryWithoutGridFocusNeverReachesTheCanvas() {
        let target = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: picture, gridSelection: nil, sections: sections)
        #expect(target == .none)
        let empty = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: picture, gridSelection: [], sections: sections)
        #expect(empty == .none)
    }

    @Test("the library pane with a focused selection is those items, in the grid's order")
    func librarySelectionIsTheItems() {
        let chosen = Set(sections.flatMap(\.items).prefix(3).map(\.id))
        let target = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: nil, gridSelection: chosen, sections: sections)
        #expect(target == .library(Array(sections.flatMap(\.items).prefix(3))))
        #expect(target.count == 3)
        #expect(target.singleItem == nil)
    }

    @Test("a selection the query has filtered out of the sections is nothing")
    func filteredOutSelectionIsNone() {
        let target = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: picture,
            gridSelection: ["/nowhere/gone.png"], sections: sections)
        #expect(target == .none)
    }

    @Test("one chosen library item is the single item; the canvas is not one")
    func singleItemIsOnlyOneLibraryItem() {
        let one = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: nil, gridSelection: [firstItem.id], sections: sections)
        #expect(one.singleItem == firstItem)
        #expect(CommandTarget.canvas(picture).singleItem == nil)
        #expect(CommandTarget.none.singleItem == nil)
    }

    @Test("titles pluralise by the count and say Image for one")
    func titlesPluralise() {
        let four = CommandTarget.library(Array(sections.flatMap(\.items).prefix(4)))
        #expect(four.exportTitle == "Export 4 Images…")
        #expect(CommandTarget.canvas(picture).exportTitle == "Export…")
        #expect(four.copyTitle == "Copy 4 Images")
        #expect(four.deleteTitle == "Delete 4 Images")
        #expect(CommandTarget.canvas(picture).deleteTitle == "Delete Image")
        #expect(CommandTarget.none.copyTitle == "Copy Image")
    }
}
