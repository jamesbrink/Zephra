import Foundation
import Testing
import ZephraEngine

@testable import Zephra

/// The selection persists pane, scope, and sort through the app's own defaults on every move,
/// so each test puts back what it found there.
@Suite("Where the window is looking", .serialized)
final class WorkspaceSelectionTests {
    private let keys = [AppSettings.workspacePane, AppSettings.libraryScope, AppSettings.librarySort]
    /// The three keys hold raw enum values, so strings are all there is to put back.
    private let saved: [String: String]

    init() {
        let defaults = UserDefaults.standard
        saved = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            defaults.string(forKey: key).map { (key, $0) }
        })
    }

    deinit {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    @Test("typing a search from the canvas brings the library up, and clearing it goes back")
    func searchBouncesToTheLibraryAndBack() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.setSearchText("fog")
        #expect(workspace.pane == .library)
        #expect(workspace.query.text == "fog")
        workspace.setSearchText("")
        #expect(workspace.pane == .canvas)
    }

    @Test("whitespace is not a search")
    func whitespaceIsNotASearch() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.setSearchText("   ")
        #expect(workspace.pane == .canvas)
    }

    @Test("someone who chose the library after searching is not yanked back when the field clears")
    func settlingInTheLibraryForgetsWhereTheSearchStarted() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.setSearchText("fog")
        workspace.pane = .canvas
        workspace.pane = .library
        workspace.setSearchText("")
        #expect(workspace.pane == .library)
    }

    @Test("moving pane closes whatever was open full size and brings a tucked prompt back")
    func movingPaneClearsTheViewerAndTheTuck() {
        let workspace = WorkspaceSelection(pane: .library)
        workspace.viewing = "a-picture.png"
        workspace.promptTucked = true
        workspace.pane = .canvas
        #expect(workspace.viewing == nil)
        #expect(workspace.promptTucked == false)
    }

    @Test("showing a scope moves to the library")
    func showingAScopeMovesToTheLibrary() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.show(scope: .favourites)
        #expect(workspace.pane == .library)
        #expect(workspace.query.scope == .favourites)
    }

    @Test("narrowing by a model or a tag moves to the library, and widening again does not move")
    func narrowingMovesWideningDoesNot() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.show(modelID: "z-image-turbo-8bit")
        #expect(workspace.pane == .library)
        #expect(workspace.query.modelID == "z-image-turbo-8bit")
        workspace.pane = .canvas
        workspace.query.modelID = nil
        #expect(workspace.pane == .canvas)
        workspace.show(tag: "portraits")
        #expect(workspace.pane == .library)
        #expect(workspace.query.tag == "portraits")
    }

    @Test("asking for a field twice hands out two tokens, so the second ask is heard")
    func focusTokensAdvanceOnEveryAsk() {
        let workspace = WorkspaceSelection(pane: .canvas)
        let before = workspace.searchFocusToken
        workspace.focusSearch()
        workspace.focusSearch()
        #expect(workspace.searchFocusToken == before + 2)
        let prompt = workspace.promptFocusToken
        workspace.focusPrompt()
        #expect(workspace.promptFocusToken == prompt + 1)
    }
}
