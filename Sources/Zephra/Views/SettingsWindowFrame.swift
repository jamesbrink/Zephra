import AppKit
import SwiftUI

/// Makes the Settings window resizable, keeps one floor under it, and opens it centred at the
/// size the tab asks for or at as much of that size as the display has room for.
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
/// person's: only a tab taller than the window grows it, because the alternative is a clipped
/// pane, and a window they made larger stays larger. Both sizes go through
/// `SettingsWindowFit`, so neither ever passes the display's visible frame — Performance is
/// taller than a laptop screen and scrolls the rest — and `contentMinSize` is
/// `SettingsTab.minimumHeight`, never the tab's own height, which is what left Performance's
/// bottom off a 1080-point display: AppKit can only clamp a window whose minimum fits.
struct SettingsWindowFrame: NSViewRepresentable {
    /// The size this tab would like to open at, before the display has its say.
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
        window.contentMinSize = CGSize(
            width: SettingsTab.openingWidth, height: SettingsTab.minimumHeight)
        // What the title bar and the tab strip take, asked of this window rather than written
        // down, and what the screen has under the menu bar. No screen at all — a window not on
        // one yet — is answered as room enough, so the tab opens at its own height.
        let chrome =
            window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).height - size.height
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? (size.height + chrome)
        let target = SettingsWindowFit.contentSize(
            opening: size, chromeHeight: chrome, visibleHeight: visible,
            floor: SettingsTab.minimumHeight)
        guard opening.done else {
            window.setContentSize(target)
            window.center()
            opening.done = true
            return constrain(window)
        }
        // A tab taller than the window currently stands at: grow to it, keeping whatever size
        // the person has chosen otherwise.
        let content = window.contentRect(forFrameRect: window.frame).size
        let grown = SettingsWindowFit.grown(current: content, toward: target)
        guard grown != content else { return }
        window.setContentSize(grown)
        constrain(window)
    }

    /// A window that just grew has not moved, so it can be hanging off the display — over the
    /// menu bar at the top, which `constrainFrameRect` is AppKit's own answer to, or under the
    /// Dock at the bottom, which it says nothing about and which is where a Settings window
    /// grown on a tab switch actually goes. So both, in that order.
    private static func constrain(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        let constrained = window.constrainFrameRect(window.frame, to: screen)
        guard let visible = screen?.visibleFrame else {
            return window.setFrame(constrained, display: true)
        }
        window.setFrame(SettingsWindowFit.placed(constrained, inside: visible), display: true)
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
        // `observe` types its closure `@Sendable`, since KVO in general calls back on whichever
        // thread wrote the property, and `styleMask` is main-actor isolated — so reading it
        // there is a warning. `assumeIsolated` rather than a hop onto the main actor, because
        // the thread is not in general doubt here: AppKit only permits `styleMask` to be
        // *mutated* on the main thread, so the notification can only ever arrive on it. Stating
        // that is both cheaper than a `Task` — which would put the flag back a turn of the run
        // loop later, after SwiftUI had already drawn one frame without it — and honest about
        // why it is safe, where silencing the warning would not have been.
        mask = window?.observe(\.styleMask) { window, _ in
            MainActor.assumeIsolated {
                guard !window.styleMask.contains(.resizable) else { return }
                window.styleMask.insert(.resizable)
            }
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
