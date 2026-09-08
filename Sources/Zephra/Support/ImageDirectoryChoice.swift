import AppKit
import ZephraEngine

/// Native folder choices; the engine drains work and changes the library after confirmation.
///
/// Both the panel and the question after it are sheets on the window they were raised from,
/// which for the Change… button in Settings > General is the Settings window (`ModalHost`). The
/// two entry points stay synchronous because their callers are buttons with nothing to wait for.
@MainActor
enum ImageDirectoryChoice {
    static func choose(store: GenerationStore, index: LibraryIndex) {
        Task { await ask(store: store, index: index) }
    }

    static func confirm(_ folder: URL?, store: GenerationStore, index: LibraryIndex) {
        Task { await ask(folder, store: store, index: index) }
    }

    private static func ask(store: GenerationStore, index: LibraryIndex) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Zephra saves images in."
        panel.directoryURL = store.outputDirectory
        guard await ModalHost.present(panel) == .OK, let chosen = panel.url else { return }
        await ask(chosen, store: store, index: index)
    }

    private static func ask(_ folder: URL?, store: GenerationStore, index: LibraryIndex) async {
        let destination = folder ?? ImageLibrary.pictures().root
        let source = store.outputDirectory
        guard destination.resolvingSymlinksInPath() != source.resolvingSymlinksInPath() else { return }
        switch await ModalHost.present(alert(moving: source, to: destination)) {
        case .alertFirstButtonReturn: apply(folder, moving: false, store: store, index: index)
        case .alertSecondButtonReturn: apply(folder, moving: true, store: store, index: index)
        default: break
        }
    }

    /// The question itself, apart from the asking, so what the keyboard does to it can be pinned
    /// without a window. Keep in Place is added first, so Return gives the answer that moves no
    /// files; Cancel is added last, where `NSAlert` finds it and gives it Escape.
    static func alert(moving source: URL, to destination: URL) -> NSAlert {
        ModalHost.warning(
            "Move existing images?",
            "New images will be saved to \(destination.path). Move your images, albums, sources, and Recently Deleted from \(source.path), or keep them where they are. Keeping them in place shows the library in the selected folder; choose the old folder again to see its images. Existing files will not be overwritten.",
            buttons: ["Keep in Place", "Move Images", "Cancel"]
        )
    }

    private static func apply(_ folder: URL?, moving: Bool, store: GenerationStore, index: LibraryIndex) {
        Task {
            do {
                let warnings = try await store.changeImageDirectory(
                    to: folder ?? ImageLibrary.pictures().root, moving: moving, index: index)
                AppSettings.recordImagesDirectory(folder)
                if !warnings.isEmpty {
                    await ModalHost.report("Images moved with a warning", warnings.joined(separator: "\n\n"))
                }
            } catch {
                await ModalHost.report("Images folder was not changed", error.localizedDescription)
            }
        }
    }
}
