import AppKit
import SwiftUI
import Testing

@testable import Zephra

/// `ReferencePlaceholder` draws a dashed hairline, and while a drop is in flight a solid accent
/// one, in an overlay over its button — the same shape `WallSquareChrome` uses to keep a wash
/// off the click. This is the test that says the overlay does not take it either: a real
/// mouse-down and mouse-up sent through a window, not an accessibility press, which goes
/// straight to the action and would pass even with the overlay eating every click.
@Suite("The reference placeholder's chrome lets the click through")
struct ReferencePlaceholderChromeTests {
    @MainActor
    private final class Presses {
        var count = 0
    }

    @Test("a click on a hovered, targeted placeholder reaches the button under its chrome")
    @MainActor
    func clickReachesTheButton() async {
        let count = await clicks(targeted: true)
        #expect(count == 1, "the dashed-to-solid overlay took the click")
    }

    @Test("with no drop in flight the click still reaches the button")
    @MainActor
    func bareClickReachesTheButton() async {
        let count = await clicks(targeted: false)
        #expect(count == 1)
    }

    /// Hosts a button wearing `ReferencePlaceholder` as its label in an off-screen window,
    /// hovers and clicks its middle, and says how many times the action ran.
    @MainActor
    private func clicks(targeted: Bool) async -> Int {
        let presses = Presses()
        let side: CGFloat = 64
        let view = Button {
            presses.count += 1
        } label: {
            ReferencePlaceholder(isTargeted: targeted)
        }
        .buttonStyle(.plain)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        // Off every screen and never ordered in front: the tests run beside whatever the
        // person is doing, and nothing here may take the keyboard or the pointer from them.
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: side, height: side),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        await Task.yield()

        let middle = NSPoint(x: side / 2, y: side / 2)
        // A hover first, so the placeholder's own hovered fill is up too when the click lands.
        if let moved = NSEvent.mouseEvent(
            with: .mouseMoved, location: middle, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0)
        {
            window.sendEvent(moved)
        }
        await Task.yield()

        for (kind, number) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
            guard let event = NSEvent.mouseEvent(
                with: kind, location: middle, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: number, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0)
            else { continue }
            window.sendEvent(event)
        }
        // The action runs on the main actor after the up lands; give the run loop a turn.
        for _ in 0..<5 where presses.count == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        window.close()
        return presses.count
    }
}
