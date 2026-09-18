import AppKit
import SwiftUI
import Testing
import ZephraEngine

@testable import Zephra

@MainActor
@Suite("A library reveal selects what it scrolls to")
struct LibraryRevealSelectionTests {
    @Test("the grid replaces the old selection before finishing a reveal", arguments: [0, 1, 2])
    func revealSelectsTarget(scenario: Int) async throws {
        let index = LibraryIndex.preview(count: 4)
        let listed = index.sections.flatMap(\.items)
        let target = try #require(listed.last)
        let previous = try #require(listed.first)
        let workspace = WorkspaceSelection(pane: .library)
        let selection = LibrarySelection()
        selection.apply(LibraryCursor.Outcome(ids: [previous.id], anchor: previous.id))
        // Cover a pending reveal on mount, an already visible grid, and a delayed listing.
        if scenario == 0 { workspace.reveal(target) }
        if scenario == 2 {
            index.query.text = "no matching image for this reveal"
            #expect(index.sections.isEmpty)
        }
        let host = NSHostingView(rootView: LibraryGrid(selection: selection)
            .environment(index)
            .environment(workspace)
            .environment(GenerationStore.preview(state: .ready)))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        if scenario != 0 {
            try await Task.sleep(for: .milliseconds(100))
            workspace.reveal(target)
        }
        if scenario == 2 {
            try await Task.sleep(for: .milliseconds(100))
            #expect(workspace.unansweredReveal == target.id)
            index.query = LibraryQuery()
        }
        for _ in 0..<100 where workspace.unansweredReveal != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(workspace.unansweredReveal == nil)
        #expect(selection.ids == [target.id])
        #expect(selection.anchor == target.id)
        // Later updates must preserve the user's next selection rather than replay the reveal.
        selection.apply(LibraryCursor.Outcome(ids: [previous.id], anchor: previous.id))
        index.query.text = "no matching image for this reveal"
        index.query = LibraryQuery()
        try await Task.sleep(for: .milliseconds(100))
        #expect(selection.ids == [previous.id])
    }
}
