import AppKit
import Foundation

/// Asking for a picture to edit, through the standard open panel.
enum ReferenceImagePicker {
    /// Shows the panel and returns the chosen file, or nil when the user cancels. Only the
    /// choice is made here; the read and the re-encode belong off the main actor, which is
    /// where `GenerationStore.adoptReference` puts them. `role` says what the panel's message
    /// calls the picture, since a clip's first frame is not "edited" the way klein's is.
    ///
    /// A sheet on the window it was raised from, like every other panel in the app: both
    /// callers are button actions, so each starts a `Task` and awaits it there.
    @MainActor
    static func choose(role: ReferenceRole = .reference) async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = role.openPanelMessage
        guard await ModalHost.present(panel) == .OK else { return nil }
        return panel.url
    }
}
