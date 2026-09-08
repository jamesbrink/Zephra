import Foundation
import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

/// The one shortcut in the menu bar that a text view already means something by.
///
/// ⌘⌫ in an `NSTextView` is `deleteToBeginningOfLine:`, and a menu item's key equivalent is
/// matched before the responder chain is offered the keystroke — so the item has to stand down
/// while the prompt has the caret, or the picture goes to Recently Deleted instead of the line
/// being trimmed. These pin that gate, and pin that it stops there: the rest of the file
/// commands keep their target while the prompt is where the typing goes.
@Suite("What Command Delete is about while the caret is in the prompt")
struct CommandTargetFocusTests {
    private let sections = LibraryIndex.preview(count: 6).sections
    private let picture = PreviewImages.sample()

    private var canvasTarget: CommandTarget {
        CommandTarget.resolve(
            pane: .canvas, isShowingRun: false, current: picture, gridSelection: nil, sections: sections)
    }

    @Test("a picture on the canvas with the caret in the prompt is nothing to delete")
    func canvasPictureIsNotDeletableWhileTyping() {
        #expect(canvasTarget == .canvas(picture))
        #expect(canvasTarget.whileTyping(true) == .none)
        #expect(canvasTarget.whileTyping(true).isEmpty)
    }

    @Test("the same picture with the caret anywhere else is the picture")
    func canvasPictureIsDeletableOtherwise() {
        #expect(canvasTarget.whileTyping(false) == .canvas(picture))
    }

    @Test("the other file commands keep the picture while the prompt has the keyboard")
    func onlyTheDeletionStandsDown() {
        // `resolve` is the target every other item reads, and it does not ask about the prompt:
        // the caret stays in the prompt while the capsule is tucked away, so gating them all
        // would grey out most of the File menu for most of the time a picture is on screen.
        #expect(canvasTarget.count == 1)
        #expect(canvasTarget.exportTitle == "Export…")
        #expect(!canvasTarget.isEmpty)
    }

    @Test("a library selection is unaffected: the grid cannot have the keyboard while the prompt does")
    func libraryTargetIsUnchanged() {
        let chosen = Set(sections.flatMap(\.items).prefix(2).map(\.id))
        let target = CommandTarget.resolve(
            pane: .library, isShowingRun: false, current: nil, gridSelection: chosen, sections: sections)
        #expect(target.whileTyping(false) == target)
        // Belt and braces rather than a rule of the interface: were a stale scene value ever to
        // say the prompt had the caret from the library pane, standing down is the safe answer.
        #expect(target.whileTyping(true) == .none)
    }

    @Test("nothing to act on stays nothing either way")
    func noTargetStaysNone() {
        #expect(CommandTarget.none.whileTyping(true) == .none)
        #expect(CommandTarget.none.whileTyping(false) == .none)
    }
}
