import OSLog
import SwiftUI
import ZephraCore
import ZephraEngine

/// What the composition root decides before the window is up, for `make logs`.
private nonisolated let launchLogger = Logger(subsystem: "io.zephra", category: "launch")

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

    /// The model chosen last time, or the one this Mac would be started on when nothing was
    /// chosen, when the saved identifier belongs to a build that no longer ships that model,
    /// or when this Mac cannot hold what was saved.
    ///
    /// That last case is what a Mac that has lost memory looks like — a wired limit turned
    /// back down, a saved choice carried to a smaller machine over the same preferences, a
    /// measured figure revised upwards by a later build. The saved model is greyed everywhere
    /// it is listed now, so opening on it would leave the window pointing at a model no door
    /// in the app will load; the step is made here, once, before the store is built, rather
    /// than by the engine's own fallback after a survey. Whether the model is still on the
    /// disk is a separate question and stays the store's, at bootstrap, from the backend.
    static func savedModel(
        fitting budget: MemoryBudget, defaults: UserDefaults = AppSettings.store
    ) -> ModelDescriptor {
        let saved = defaults.string(forKey: AppSettings.selectedModelID)
        guard let model = saved.flatMap(ModelCatalog.descriptor(id:)) else {
            return ModelCatalog.default(fitting: budget)
        }
        let fit = ModelCatalog.fit(model, budget: budget)
        guard !fit.isSelectable else { return model }
        let stepped = ModelCatalog.default(fitting: budget)
        launchLogger.info(
            """
            saved model \(model.id, privacy: .public) needs \
            \(fit.label ?? "more than this Mac has", privacy: .public) and cannot be chosen \
            here; opening on \(stepped.id, privacy: .public)
            """)
        return stepped
    }
}
