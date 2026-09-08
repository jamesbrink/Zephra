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
    static var window: NSWindow? {
        if let host = hosting(NSApp.keyWindow) { return host }
        if let host = hosting(NSApp.mainWindow) { return host }
        return NSApp.windows.first { $0.isVisible && $0.canBecomeKey && !$0.isSheet }
    }

    private static func hosting(_ window: NSWindow?) -> NSWindow? {
        guard let window, window.isVisible else { return nil }
        return window.sheetParent ?? window
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
