import AppKit
import SwiftUI
import Testing
import ZephraEngine

@testable import Zephra

/// The canvas's picture zooms, and at fit it is still the picture it was: a click tucks the
/// prompt and a right click opens its menu, both through SwiftUI's own gestures laid over the
/// AppKit scroll view. Real mouse events, posted to the application's queue for an off-screen
/// window, on a store frozen over a finished picture.
@Suite("Clicking a zoomable picture", .serialized)
@MainActor
struct ZoomablePictureClickTests {
    @Test("at fit a click on the picture tucks the prompt, and one on the letterbox does not")
    func clickAtFitTucks() async throws {
        let workspace = WorkspaceSelection(pane: .canvas)
        let window = canvas(workspace)
        defer { window.close() }
        let scroll = try #require(await window.scrollView(), "the picture was decoded and laid out")
        #expect(scroll.isAtFit)

        try await window.click(.leftMouseDown, .leftMouseUp, at: window.pictureMiddle(of: scroll))
        #expect(workspace.promptTucked, "the click reached the canvas's tap gesture")

        // A square picture in a wide pane: the far left is graphite, not picture.
        try await window.click(.leftMouseDown, .leftMouseUp, at: NSPoint(x: 20, y: 300))
        #expect(workspace.promptTucked, "a click on the letterbox left the tuck alone")
    }

    @Test("a right click opens the picture's menu at fit and zoomed in")
    func rightClickOpensTheMenu() async throws {
        let window = canvas(WorkspaceSelection(pane: .canvas))
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        let menus = MenuWatch()
        defer { menus.stop() }

        try await window.click(.rightMouseDown, .rightMouseUp, at: window.pictureMiddle(of: scroll))
        #expect(menus.titles.contains("Use as Reference"), "the right click at fit opened the picture's own menu: \(menus.titles)")
        menus.titles = []

        scroll.zoom(to: 3)
        await window.settle()
        #expect(!scroll.isAtFit)
        try await window.click(.rightMouseDown, .rightMouseUp, at: window.pictureMiddle(of: scroll))
        #expect(menus.titles.contains("Use as Reference"), "the right click zoomed in opened it too: \(menus.titles)")
    }

    @Test("zoomed in, a click is the pan's and not the tuck's")
    func zoomedClickPans() async throws {
        let workspace = WorkspaceSelection(pane: .canvas)
        let window = canvas(workspace)
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        scroll.zoom(to: 2)
        await window.settle()

        try await window.click(.leftMouseDown, .leftMouseUp, at: window.pictureMiddle(of: scroll))
        #expect(!workspace.promptTucked)
    }

    private func canvas(_ workspace: WorkspaceSelection) -> ZoomTestWindow {
        let store = GenerationStore.preview(state: .ready, image: PreviewImages.sample())
        return ZoomTestWindow(
            CanvasView()
                .environment(ImageCache())
                .environment(workspace)
                .environment(LibraryIndex.preview(count: 0))
                .environment(ThumbnailCache())
                .environment(store))
    }

    /// Collects the titles of menus that begin tracking, and cancels each at once so the test
    /// goes on.
    @MainActor
    private final class MenuWatch: NSObject {
        var titles: [String] = []
        private var tracking: NSMenu?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(began(_:)), name: NSMenu.didBeginTrackingNotification,
                object: nil)
        }

        @objc private func began(_ note: Notification) {
            tracking = note.object as? NSMenu
            titles += tracking?.items.map(\.title) ?? []
            RunLoop.main.perform(inModes: [.eventTracking, .default]) { [weak self] in
                MainActor.assumeIsolated { self?.tracking?.cancelTrackingWithoutAnimation() }
            }
        }

        func stop() { NotificationCenter.default.removeObserver(self) }
    }
}
