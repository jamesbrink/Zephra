import AppKit
import Foundation

/// Asking for a picture to edit, through the standard open panel.
enum ReferenceImagePicker {
    /// Shows the panel and returns the chosen file, or nil when the user cancels. Only the
    /// choice is made here; the read and the re-encode belong off the main actor, which is
    /// where `GenerationStore.adoptReference` puts them.
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture to edit"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
