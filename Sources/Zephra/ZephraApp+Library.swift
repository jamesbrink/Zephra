import SwiftUI
import ZephraCore
import ZephraEngine

/// What the composition root does that names no backend: wiring the library to the store, and
/// reading which model the last launch was on.
///
/// Apart from `ZephraApp.swift` so that file holds only what may not live anywhere else — the
/// scene and the one list of concrete backends — and stays within its length; `make lint-layers`
/// exempts that file alone from the backend-import rule, and nothing here needs the exemption.
extension ZephraApp {
    /// Starts the library reading the folder, and tells it about the images this session makes
    /// and unmakes.
    ///
    /// A saved image is handed to the index by path, one header read and a sorted insert; a
    /// deleted one is a rescan, because the store moves the file to Recently Deleted and a path
    /// that has gone is not something the index can be told about in place. Either way the folder
    /// watch would notice in its own time — this is only so the grid moves at once.
    func openLibrary() {
        index.start()
        // Only the `viewer` screenshot build has an answer here.
        if let viewing = InterfacePreview.viewing(in: index) { workspace.viewing = viewing }
        thumbnails.sweep()
        store.onImageSaved = { url in
            index.insert(fileAt: url)
            // The image was attached its file before this was called, so the one at this URL
            // is in the session's history; an image the history has let go is named only as
            // saved.
            let image = store.history.first { $0.fileURL == url }
            BackgroundNotices.post(
                .imageSaved(prompt: image?.settings.prompt ?? "", isClip: image?.isVideo ?? false))
        }
        store.onImageDeleted = { _ in Task { await index.rescanNow() } }
        // The reverse direction: a delete made through the index — the grid, the viewer, the
        // sidebar wall, or the canvas's own menu — never goes through the store, so the store
        // is told separately when one of the files it might be showing is gone.
        index.onRecentlyDeleted = { urls in
            for url in urls { store.forget(fileAt: url) }
        }
    }

    /// The model chosen last time, or the largest one this Mac can actually run when nothing
    /// was chosen or the saved identifier belongs to a build that no longer ships that model.
    ///
    /// A saved choice is honoured whatever its size: a model that pages at its default size
    /// still runs at a smaller one, and that is the user's call to make. Whether it is still
    /// on the disk is the store's to find out, at bootstrap, from the backend.
    static func savedModel(fitting budget: MemoryBudget) -> ModelDescriptor {
        let saved = UserDefaults.standard.string(forKey: AppSettings.selectedModelID)
        return saved.flatMap(ModelCatalog.descriptor(id:))
            ?? ModelCatalog.default(fitting: budget)
    }
}
