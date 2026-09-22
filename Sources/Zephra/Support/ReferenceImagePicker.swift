import AppKit
import Foundation
import ZephraCore

/// Asking for pictures to edit, through the standard open panel.
enum ReferenceImagePicker {
    /// Shows the panel and returns the chosen files, or nothing when the user cancels. Only the
    /// choice is made here; the read and the re-encode belong off the main actor, which is
    /// where `GenerationStore.adoptReferences` puts them. `role` says what the panel's message
    /// calls the pictures, since a clip's first frame is not "edited" the way klein's is.
    ///
    /// `upTo` is how many the model would read: one turns multiple selection off, so a
    /// one-picture model's panel behaves exactly as it always has, and anything more turns it
    /// on. The panel is not asked to enforce the number — `NSOpenPanel` has no such knob — so
    /// the answer is trimmed here rather than pretending it cannot happen.
    ///
    /// A sheet on the window it was raised from, like every other panel in the app: every
    /// caller is a button action, so each starts a `Task` and awaits it there.
    @MainActor
    static func choose(role: ReferenceRole = .reference, upTo: Int = 1) async -> [URL] {
        let most = max(1, min(upTo, ReferenceLimits.maximumPictures))
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = most > 1
        panel.canChooseDirectories = false
        panel.message = role.openPanelMessage(upTo: most)
        guard await ModalHost.present(panel) == .OK else { return [] }
        return Array(panel.urls.prefix(most))
    }
}
