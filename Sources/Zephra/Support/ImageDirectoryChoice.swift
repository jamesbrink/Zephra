import AppKit
import ZephraEngine

/// Native folder choices; the engine drains work and changes the library after confirmation.
@MainActor
enum ImageDirectoryChoice {
    static func choose(store: GenerationStore, index: LibraryIndex) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Zephra saves images in."
        panel.directoryURL = store.outputDirectory
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        confirm(chosen, store: store, index: index)
    }

    static func confirm(_ folder: URL?, store: GenerationStore, index: LibraryIndex) {
        let destination = folder ?? ImageLibrary.pictures().root
        let source = store.outputDirectory
        guard destination.resolvingSymlinksInPath() != source.resolvingSymlinksInPath() else { return }
        let alert = NSAlert()
        alert.messageText = "Move existing images?"
        alert.informativeText = "New images will be saved to \(destination.path). Move your images, albums, sources, and Recently Deleted from \(source.path), or keep them where they are. Keeping them in place shows the library in the selected folder; choose the old folder again to see its images. Existing files will not be overwritten."
        alert.addButton(withTitle: "Move Images")
        alert.addButton(withTitle: "Keep in Place")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: apply(folder, moving: true, store: store, index: index)
        case .alertSecondButtonReturn: apply(folder, moving: false, store: store, index: index)
        default: break
        }
    }

    private static func apply(_ folder: URL?, moving: Bool, store: GenerationStore, index: LibraryIndex) {
        Task {
            do {
                let warnings = try await store.changeImageDirectory(
                    to: folder ?? ImageLibrary.pictures().root, moving: moving, index: index)
                AppSettings.recordImagesDirectory(folder)
                if !warnings.isEmpty { report("Images moved with a warning", warnings.joined(separator: "\n\n")) }
            } catch {
                report("Images folder was not changed", error.localizedDescription)
            }
        }
    }

    private static func report(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
