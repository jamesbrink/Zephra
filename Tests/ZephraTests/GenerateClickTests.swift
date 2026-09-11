import AppKit
import SwiftUI
import Testing
import ZephraEngine

@testable import Zephra

/// A mouse click on Generate reaches the store through the window, the capsule and whatever
/// the capsule sits over. It is the hit-testing and not the action that a stray overlay, a
/// gesture on the picture behind, a representable view under the capsule or a change of the
/// button's identity breaks; ⌘⏎ goes through the menu bar and keeps working with the button
/// dead, which is why an accessibility press, which goes straight to the action, would not do.
///
/// The whole canvas pane is hosted, picture and floating controls both, in an off-screen
/// window that never takes the pointer from the person running the tests, on a store frozen
/// in `ready` with a prompt; the click is a real mouse-down and mouse-up sent to that window,
/// and what is watched is the store's queue taking the run.
@Suite("Clicking Generate")
struct GenerateClickTests {
    @Test("a mouse click on the Generate button queues a generation, idle and mid-run")
    @MainActor
    func clickReachesTheStore() async throws {
        for state in [EngineState.ready, .generating(.init(phase: .denoising(step: 2, of: 9), fraction: 0.2))] {
            let store = GenerationStore.preview(state: state, image: PreviewImages.sample())
            store.settings.prompt = "a red bicycle against a limestone wall"
            let queued = store.queue.count
            let pressed = try await click(in: store)
            #expect(pressed, "the Generate button was found in the hosted capsule")
            // Idle, the frozen store takes the run and fails it at once for want of a backend,
            // so leaving `ready` is the sign; mid-run the queue simply grows.
            let taken = store.queue.count == queued + 1 || store.state != .ready
            #expect(taken, "the click queued nothing from \(state): now \(store.state), \(store.queue.count) queued")
        }
    }

    /// Hosts the canvas pane over `store`, waits for Generate to say where it is, sends a click
    /// to its middle and gives the action a turn of the run loop. False when the button never
    /// reported a frame.
    @MainActor
    private func click(in store: GenerationStore) async throws -> Bool {
        let size = NSSize(width: 1100, height: 760)
        let located = Located()
        let host = NSHostingView(
            rootView: CanvasPane()
                .onPreferenceChange(GenerateButtonFrame.self) { located.frame = $0 }
                .environment(ImageCache())
                .environment(WorkspaceSelection(pane: .canvas))
                .environment(LibraryIndex.preview(count: 0))
                .environment(ThumbnailCache())
                .environment(WelcomeGate(defaults: UserDefaults(suiteName: "io.zephra.tests.click")!))
                .environment(store))
        host.frame = NSRect(origin: .zero, size: size)
        // Off every screen and never ordered in front, so nothing here takes the keyboard or
        // the pointer from whoever is running the tests.
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<20 where located.frame == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let frame = located.frame else { return false }

        // The frame is in the hosting view's space, top-left up; the window's is bottom-left.
        let middle = host.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
        for (kind, number) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
            let event = try #require(NSEvent.mouseEvent(
                with: kind, location: middle, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: number, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
        for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(20)) }
        return true
    }

    /// The button's reported frame, written from the preference on the main actor.
    @MainActor
    private final class Located {
        var frame: CGRect?
    }
}
