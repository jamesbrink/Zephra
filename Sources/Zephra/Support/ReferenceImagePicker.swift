import AppKit
import Foundation

/// Asking for a picture to edit, through the standard open panel.
enum ReferenceImagePicker {
    /// Shows the panel and returns the chosen picture as PNG bytes, or nil when the user cancels
    /// or the file is not a picture.
    @MainActor
    static func choose() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture to edit"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ReferenceImageEncoder.pngData(contentsOf: url)
    }
}
