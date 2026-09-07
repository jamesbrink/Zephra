import AppKit
import SwiftUI
import Testing

@testable import Zephra

/// The wall's squares are buttons under a hover wash and a selection ring. A click has to reach
/// the button through both, and this is the test that says it does: a real mouse-down and
/// mouse-up sent through a window, not an accessibility press, which goes straight to the
/// action and would pass with the chrome eating every click.
@Suite("The wall square's chrome lets the click through")
struct WallSquareChromeTests {
    @MainActor
    private final class Presses {
        var count = 0
    }

    @Test("a click on a washed, ringed square reaches the button under the chrome")
    @MainActor
    func clickReachesTheButton() async {
        let presses = Presses()
        let count = await clicks(hovered: true, showing: true) { presses.count += 1 }
        #expect(count == 1, "the wash or the ring took the click")
    }

    @Test("with no chrome up the click reaches the button, which is what the chrome must match")
    @MainActor
    func bareClickReachesTheButton() async {
        let count = await clicks(hovered: false, showing: false) {}
        #expect(count == 1)
    }

    /// Hosts a plain button wearing the chrome in an off-screen window, clicks its middle, and
    /// says how many times the action ran.
    @MainActor
    private func clicks(hovered: Bool, showing: Bool, then: @escaping () -> Void) async -> Int {
        let presses = Presses()
        let side: CGFloat = 80
        let view = Button {
            presses.count += 1
            then()
        } label: {
            Color.gray.frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .modifier(WallSquareChrome(isHovered: hovered, isShowing: showing))

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
