import AppKit

/// The one sentence asked before an image is deleted for good.
///
/// One place rather than one per entry point, because there are three — the delete key, the
/// notice's button, and ⌘⌫ from the menu bar — and a destructive confirmation that is worded
/// differently depending on how it was reached is a confirmation nobody reads.
///
/// An `NSAlert` rather than SwiftUI's `.alert`, for the same reason `ImageExport` uses one: it
/// can be raised from a menu command, which is not a view and has nowhere to hang a
/// presentation binding.
enum PurgeConfirmation {
    /// Asks, and answers whether to go ahead. Deleting into Recently Deleted never asks — the
    /// file sits in a folder for thirty days and Put Back is right there. This is the other
    /// one, and it says what really happens: `ImageLibrary.discard` moves the file to the
    /// Finder's Trash where there is one, so the sentence does not promise a permanence the
    /// code does not deliver.
    static func confirm(count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "Delete this image?"
            : "Delete these \(count) images?"
        alert.informativeText = count == 1
            ? "It will be moved to the Trash."
            : "They will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        // The destructive button is first, so Return does not fall on it by accident.
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}
