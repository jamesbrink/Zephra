import AppKit

/// Where a question goes, and what the keyboard does to its buttons. Two rules, written down
/// once here rather than at each of the dozen places that ask something, because both are
/// AppKit's rather than ours and both were got wrong.
///
/// **A question about a window belongs on that window.** `runModal()` puts an alert or a file
/// panel in front of the whole application, anchored to nothing: on another Space it drags the
/// user there, and it blocks every window rather than the one it is about. `beginSheetModal(for:)`
/// hangs it off the window whose contents it concerns, and that window is simply `NSApp.keyWindow`
/// — the Settings window when a Settings row raised the panel, the main window when the canvas or
/// the library did, because whichever one was clicked in is the one holding the keyboard. There is
/// nothing to work out beyond that. `runModal()` stays only as the fallback for the case that
/// genuinely has no window: Zephra is a single `Window` scene and ⌘W closes it, so a menu command
/// can be the only thing on screen.
///
/// Reaching for `NSAlert` rather than SwiftUI's `.alert` is still right, for the reason it always
/// was: these questions are raised from menu commands, and a menu command is not a view and has
/// nowhere to hang a presentation binding. That was never a reason to run one application-modal.
///
/// **The first button added is the one Return presses**, and `hasDestructiveAction` only tints a
/// button red — it does not move the default off it. A button titled exactly "Cancel" is given
/// Escape, and that assignment *wins*: added first, "Cancel" takes Escape and the alert is left
/// with no Return button at all. So the safe answer is made the default in the way that suits the
/// shape of the question, and `warning` is the one place either is spelled:
///
/// - Three answers, one of which is safe and does something ("Keep in Place", "Keep Both"): add
///   the safe one first so it takes Return, the other in the middle, "Cancel" last for Escape.
/// - Two answers, where the only safe one is Cancel: keep the consequential button first, which
///   is where the Mac draws the rightmost button, and clear its Return (`destructive:`, or
///   `guarded:` where nothing is lost). The alert then has no default at all — Escape cancels,
///   Return does nothing, and no single keystroke can confirm a deletion. Reordering instead
///   would not do: "Cancel" added first takes Escape, and the destructive button behind it
///   inherits nothing, so the layout would be wrong for no gain.
@MainActor
enum ModalHost {
    /// The window a sheet should hang from, or nil when there is none and the question has to
    /// stand on its own. A sheet that is itself key answers with the window it is attached to,
    /// since a sheet cannot host a sheet.
    ///
    /// A window already showing one answers nil, and that case is load-bearing rather than
    /// tidy: "Choose File…" in `ReferencePickerSheet` is raised from inside a sheet on the
    /// main window, so the window this would otherwise pick is the very one the picker is
    /// attached to. AppKit does not refuse a second sheet there, it *queues* it — it would
    /// appear only once the picker closed, and the caller is awaiting the panel before closing
    /// anything, so the button would read as dead until the picker was cancelled by hand. Every
    /// candidate is tested, the last one included: unwrapping a key sheet to its parent and
    /// then falling through would otherwise offer that same parent again.
    static var window: NSWindow? {
        // Whether the question has a window of its own is asked first, and separately from
        // whether that window can take a sheet. They are different questions and collapsing
        // them sends the panel to the wrong place: a picker sheet open on the main window with
        // Settings also open would reject the main window as occupied and then find Settings in
        // the scan, hanging a file panel about the canvas off the Settings window, possibly on
        // another Space. So a window that owns the question is committed to — as a sheet host
        // when it is free, and as application-modal when it is not — and the scan is only for
        // the case with no owner at all, which a single-window app reaches whenever Command W
        // has closed it.
        if let owner = originating(NSApp.keyWindow) ?? originating(NSApp.mainWindow) {
            return free(owner) ? owner : nil
        }
        return NSApp.windows.first { $0.isVisible && $0.canBecomeKey && free($0) }
    }

    /// The window a question raised right now belongs to, free or not: the one given, or the
    /// window it is a sheet on, since a sheet's question is really its parent's.
    private static func originating(_ window: NSWindow?) -> NSWindow? {
        guard let window, window.isVisible else { return nil }
        return window.sheetParent ?? window
    }

    /// Whether a window can take a sheet right now: it is not one itself, and is not already
    /// showing one.
    private static func free(_ window: NSWindow) -> Bool {
        !window.isSheet && window.attachedSheet == nil
    }

    /// Asks `alert` as a sheet on `window`, and answers which button was pressed.
    static func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    /// The same for a file panel. `NSOpenPanel` is an `NSSavePanel`, so this is both of them.
    static func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        guard let window else { return panel.runModal() }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    /// A question whose buttons are added in `titles` order — first is rightmost, and first is
    /// where Return lands unless it is taken off. `destructive` names the answer that loses
    /// something: it is tinted red and Return is taken off it. `guarded` names one that loses
    /// nothing but is not to be given by a stray keystroke either — a folder migration — and
    /// only takes Return off. Either way the alert is then left with no default at all, which is
    /// the right answer for a two-button question whose only safe reply is Cancel.
    static func warning(
        _ message: String,
        _ informative: String,
        buttons titles: [String],
        destructive: String? = nil,
        guarded: String? = nil
    ) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        for title in titles { alert.addButton(withTitle: title) }
        if let destructive, let button = alert.buttons.first(where: { $0.title == destructive }) {
            button.hasDestructiveAction = true
            if button.keyEquivalent == "\r" { button.keyEquivalent = "" }
        }
        if let guarded, let button = alert.buttons.first(where: { $0.title == guarded }),
            button.keyEquivalent == "\r"
        {
            button.keyEquivalent = ""
        }
        return alert
    }

    /// Something to say rather than something to decide: one button, and nothing to read back.
    static func report(_ message: String, _ informative: String, style: NSAlert.Style = .informational) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = style
        _ = await present(alert)
    }
}
