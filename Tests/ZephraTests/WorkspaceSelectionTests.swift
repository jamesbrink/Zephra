import Foundation
import Testing
import ZephraCore
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

    @Test("revealing a picture brings the library up, closes the viewer and selects it")
    func revealingBringsTheLibraryUp() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.viewing = "something-else.png"
        let item = Self.item(named: "a-picture.png")
        workspace.reveal(item)
        #expect(workspace.pane == .library)
        #expect(workspace.viewing == nil)
        #expect(workspace.revealing == item.id)
    }

    @Test("the viewer goes down even when the library was already the pane up")
    func revealingClosesTheViewerWithoutMovingPane() {
        let workspace = WorkspaceSelection(pane: .library)
        workspace.viewing = "something-else.png"
        workspace.reveal(Self.item(named: "a-picture.png"))
        #expect(workspace.pane == .library)
        #expect(workspace.viewing == nil)
    }

    @Test("a query that would not list the picture is widened; the sort is kept")
    func revealingWidensAQueryThatHidesThePicture() {
        let workspace = WorkspaceSelection(
            pane: .canvas,
            query: LibraryQuery(scope: .favourites, text: "fog", tag: "night", sort: .oldestFirst))
        workspace.reveal(Self.item(named: "a-picture.png"))
        #expect(workspace.query.scope == .all)
        #expect(workspace.query.text.isEmpty)
        #expect(workspace.query.tag == nil)
        #expect(workspace.query.modelID == nil)
        #expect(workspace.query.sort == .oldestFirst, "the sort hides nothing, so it stays")
    }

    @Test("a query that already lists the picture is left exactly as it was")
    func revealingLeavesAQueryThatShowsThePictureAlone() {
        let query = LibraryQuery(scope: .all, sort: .oldestFirst)
        let workspace = WorkspaceSelection(pane: .canvas, query: query)
        workspace.reveal(Self.item(named: "a-picture.png"))
        #expect(workspace.query == query)
    }

    @Test("asking for the same picture twice hands out two tokens, so the second ask is heard")
    func revealTokensAdvanceOnEveryAsk() {
        let workspace = WorkspaceSelection(pane: .library)
        let item = Self.item(named: "a-picture.png")
        let before = workspace.revealToken
        workspace.reveal(item)
        workspace.reveal(item)
        #expect(workspace.revealToken == before + 2)
        #expect(workspace.revealing == item.id)
    }

    /// One generated picture in the library, which is all `reveal` reads: its identity and
    /// whether the query in force would list it.
    private static func item(named fileName: String) -> LibraryItem {
        let image = GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: "a harbour in the rain",
                size: ImageSize(width: 1024, height: 1024),
                steps: 8,
                guidance: 0,
                seed: 42),
            modelID: "z-image-turbo-8bit",
            duration: .seconds(3))
        return LibraryItem(
            url: URL(filePath: "/Zephra Tests/\(fileName)"),
            collection: .generated,
            provenance: .generated(GenerationRecord(image)),
            fileSize: 1_800_000,
            contentModifiedAt: Date())
    }

    @Test("the model browser is a dialog somebody opened, and is never persisted")
    func theModelBrowserIsNeverPersisted() {
        let workspace = WorkspaceSelection(pane: .canvas)
        workspace.showsModelBrowser = true
        #expect(WorkspaceSelection(pane: .canvas).showsModelBrowser == false)
    }
}
