import AppKit
import SwiftUI

/// Makes the Settings window resizable, keeps a floor under it so no tab's last row is ever
/// clipped, and opens it centred at the size the tab asks for.
///
/// SwiftUI cannot say this about a `Settings` scene. `.windowResizability(.contentSize)` takes
/// the content's maximum as the window's, which is what pinned Settings at a fixed size;
/// `.contentMinSize` leaves it fixed too, at a system width with the content stretched to fill
/// it. So the window is configured directly, from a zero-sized view living inside it, which is
/// the ordinary way to reach an `NSWindow` from SwiftUI.
///
/// Setting the resizable flag once is not enough, and this is the part worth keeping: SwiftUI
/// re-imposes its own style mask on the window whenever a tab's state changes — the Models
/// tab's inventory refresh lands a second after the tab opens — and strips the flag off again,
/// after every pass this view could hook. So the flag is *observed*: `WindowFrameView` watches
/// `styleMask` and puts it back whenever it goes, which is the one place that always has the
/// last word. It is put back eight or so times over a session and costs nothing.
///
/// The opening size and the centring happen once per launch. After that the window is the
/// person's: stepping between tabs moves the floor, and only a tab whose floor is taller than
/// the window grows it, because the alternative is a clipped pane. A window they made larger
/// stays larger.
struct SettingsWindowFrame: NSViewRepresentable {
    /// The size this tab opens at, and the least the window may be dragged to.
    let size: CGSize

    func makeCoordinator() -> Opening { Opening() }

    func makeNSView(context: Context) -> WindowFrameView {
        let view = WindowFrameView()
        view.configure = configuration(context.coordinator)
        return view
    }

    func updateNSView(_ view: WindowFrameView, context: Context) {
        view.configure = configuration(context.coordinator)
        view.applyToWindow()
    }

    private func configuration(_ opening: Opening) -> (NSWindow) -> Void {
        { window in Self.apply(size, to: window, opening: opening) }
    }

    /// Whether this window has been sized and placed yet, kept across the updates a tab change
    /// brings so the opening size is applied once and not on every switch.
    final class Opening {
        var done = false
    }

    private static func apply(_ size: CGSize, to window: NSWindow, opening: Opening) {
        window.styleMask.insert(.resizable)
        window.contentMinSize = size
        guard opening.done else {
            window.setContentSize(size)
            window.center()
            opening.done = true
            return
        }
        // A tab with a taller floor than the window currently stands at: grow to it, keeping
        // whatever size the person has chosen otherwise.
        let content = window.contentRect(forFrameRect: window.frame).size
        guard content.height < size.height || content.width < size.width else { return }
        window.setContentSize(
            CGSize(width: max(content.width, size.width), height: max(content.height, size.height)))
    }
}

/// The view that carries the configuration into the window: once as it lands in one, again on
/// every layout, and — for the resizable flag alone — whenever SwiftUI takes it away.
///
/// Resizing a window in the middle of a layout pass is what the hop to the next turn of the
/// run loop avoids. Every pass is idempotent: the floor is already the floor and the size is
/// only ever grown.
final class WindowFrameView: NSView {
    var configure: ((NSWindow) -> Void)?
    private var mask: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Watching the window this view is in now; the old watch goes with the old window, and
        // a view removed from every window watches nothing, which is why there is no `deinit`
        // (Swift 6 isolation would not let one touch this anyway).
        mask = window?.observe(\.styleMask) { window, _ in
            guard !window.styleMask.contains(.resizable) else { return }
            window.styleMask.insert(.resizable)
        }
        applyToWindow()
    }

    override func layout() {
        super.layout()
        applyToWindow()
    }

    func applyToWindow() {
        guard let window else { return }
        let configure = configure
        DispatchQueue.main.async { configure?(window) }
    }
}
