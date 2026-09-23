import AppKit
import SwiftUI
import Testing

@testable import Zephra

/// An off-screen window hosting a SwiftUI view, for the zoom suites: never ordered in front, so
/// nothing here takes the keyboard or the pointer from whoever runs the tests.
///
/// Mouse events are **posted to the application's queue** rather than handed to the window,
/// because `ZoomScrollView` decides whether a click is its own by `NSApp.currentEvent`, which
/// only the application's own event loop sets. They name this window, so they go nowhere else.
@MainActor
final class ZoomTestWindow {
    let window: NSWindow
    let host: NSHostingView<AnyView>
    private var eventNumber = 0

    init<Content: View>(_ content: Content, size: NSSize = NSSize(width: 900, height: 600)) {
        host = NSHostingView(rootView: AnyView(content))
        host.frame = NSRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
    }

    func close() { window.close() }

    /// The scroll view once the picture has been decoded and laid out, waiting up to a second.
    func scrollView() async -> ZoomScrollView? {
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            if let found = Self.find(in: host), found.documentView?.frame.width ?? 0 > 0 {
                return found
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// The middle of the picture as the scroll view shows it, in window coordinates.
    func pictureMiddle(of scroll: ZoomScrollView) -> NSPoint {
        let picture = scroll.documentView!
        let visible = picture.visibleRect
        return picture.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
    }

    /// A click of `down` and `up` at `point`, delivered through the application's event loop.
    func click(_ down: NSEvent.EventType, _ up: NSEvent.EventType, at point: NSPoint) async throws {
        for kind in [down, up] {
            eventNumber += 1
            let event = try #require(NSEvent.mouseEvent(
                with: kind, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: eventNumber, clickCount: 1, pressure: kind == down ? 1 : 0))
            NSApp.postEvent(event, atStart: false)
        }
        await settle()
    }

    /// A few turns of the run loop, for posted events and SwiftUI's updates to land.
    func settle() async {
        for _ in 0..<15 { try? await Task.sleep(for: .milliseconds(20)) }
        host.layoutSubtreeIfNeeded()
    }

    private static func find(in view: NSView) -> ZoomScrollView? {
        if let scroll = view as? ZoomScrollView { return scroll }
        for child in view.subviews {
            if let found = find(in: child) { return found }
        }
        return nil
    }
}
