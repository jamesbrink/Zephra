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
    ///
    /// A sheet on the window the question is about, like every other alert in the app: the one
    /// caller that read this answer synchronously, `LibraryIndex.delete`, is async now, and each
    /// of its own three callers is a menu action or a key handler that starts a `Task`.
    static func confirm(count: Int) async -> Bool {
        await ModalHost.present(alert(count: count)) == .alertFirstButtonReturn
    }

    /// The question itself, apart from the asking, so what the keyboard does to it can be
    /// pinned without a window. "Delete" is added first because that is where the Mac draws the
    /// rightmost button; `ModalHost.warning` is what then takes Return off it, leaving Escape on
    /// Cancel and no keystroke at all that deletes.
    static func alert(count: Int) -> NSAlert {
        ModalHost.warning(
            count == 1 ? "Delete this image?" : "Delete these \(count) images?",
            count == 1 ? "It will be moved to the Trash." : "They will be moved to the Trash.",
            buttons: ["Delete", "Cancel"],
            destructive: "Delete"
        )
    }
}
