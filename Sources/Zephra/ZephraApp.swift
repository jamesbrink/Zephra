import SwiftUI
import ZephraBackendFlux2
import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore
import ZephraEngine
import ZephraUpscaleRealESRGAN

/// The composition root. The only place that builds a store, and the only place allowed to
/// know which backend it is built on.
@main
struct ZephraApp: App {
    @NSApplicationDelegateAdaptor(AppTermination.self) private var termination
    @State private var store = ZephraApp.makeStore()
    @State private var cache = ImageCache()
    @State private var workspace = InterfacePreview.workspace() ?? WorkspaceSelection()
    @State private var index = InterfacePreview.index() ?? LibraryIndex(library: AppSettings.imageLibrary())
    @State private var thumbnails = ThumbnailCache()
    /// What the models occupy on disk, for Settings > Models. Built here with the store so the
    /// window and Settings observe the one list.
    @State private var inventory = ModelInventory(locations: AppSettings.modelLocations())
    /// The GPU runtime the Performance tab reads and tunes, over every backend at once. Built
    /// here because this is the only file allowed to name a backend.
    private static let runtime = CombinedInferenceRuntime([
        ZImageBackendFactory.runtime,
        QwenImageBackendFactory.runtime,
        Flux2BackendFactory.runtime,
    ])
    private var runtime: CombinedInferenceRuntime { Self.runtime }
    /// What this Mac's GPU may keep resident, read once here from the runtime and the
    /// `iogpu.wired_limit_mb` sysctl, then handed to every view and to the store: the model
    /// picker's wording, the tiled decode, and the fallback model all follow it.
    private static let budget = GPUMemoryBudget.forThisMachine(runtime: runtime)

    var body: some Scene {
        // One window, not a group: everything a window would own is app-wide state built
        // above, so a second one could only mirror the first. `Window` reopens on a Dock
        // click and lists itself under the Window menu; see ROADMAP for per-window state.
        Window("Zephra", id: "main") {
            RootView()
                .environment(store)
                .environment(cache)
                .environment(workspace)
                .environment(index)
                .environment(thumbnails)
                .environment(\.memoryBudget, Self.budget)
                // The appearance preference is applied to the application from the main
                // window, so it lands before the first frame and follows the picker in
                // Settings; see `AppearanceApplier`.
                .applyingAppearancePreference()
                // Remembered here rather than in the menu, so a model the engine stepped onto
                // by itself — the saved one having gone from the disk — is the one the next
                // launch opens on. The tiled decode is not decided here: the store chooses it
                // for each run's own model as the run starts; see `GenerationStore+Tiling`.
                .onChange(of: store.descriptor, initial: true) { _, model in
                    AppSettings.write(model.id, to: AppSettings.selectedModelID)
                }
                .task {
                    termination.shutdown = {
                        // Store first: its last save calls `onImageSaved` -> `index.insert`,
                        // which must land before the index stops taking anything.
                        await store.shutdown()
                        await index.shutdown()
                        let runtime = Self.runtime
                        await Task.detached { runtime.synchronize() }.value
                    }
                    openLibrary()
                }
        }
        .defaultSize(width: 1200, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            ZephraCommands(store: store, workspace: workspace)
            WorkspaceCommands(workspace: workspace, store: store)
            LibraryCommands(workspace: workspace)
            ThumbnailSizeCommands()
            AboutCommands()
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(inventory)
                .environment(index)
                .environment(\.inferenceRuntime, runtime)
                .environment(\.memoryBudget, Self.budget)
        }
        // The window takes each tab's own height (`SettingsTab.height`), shrinking as well
        // as growing, rather than standing at the tallest tab's for all four.
        .windowResizability(.contentSize)
    }

    /// Starts the library reading the folder, and tells it about the images this session makes
    /// and unmakes.
    ///
    /// A saved image is handed to the index by path, one header read and a sorted insert; a
    /// deleted one is a rescan, because the store deletes to the system Trash and a path that
    /// has gone is not something the index can be told about in place. Either way the folder
    /// watch would notice in its own time — this is only so the grid moves at once.
    private func openLibrary() {
        index.start()
        // Only the `viewer` screenshot build has an answer here.
        if let viewing = InterfacePreview.viewing(in: index) { workspace.viewing = viewing }
        thumbnails.sweep()
        store.onImageSaved = { url in index.insert(fileAt: url) }
        store.onImageDeleted = { _ in Task { await index.rescanNow() } }
        // The reverse direction: a delete made through the index — the grid, the viewer, the
        // sidebar wall, or the canvas's own menu — never goes through the store, so the store
        // is told separately when one of the files it might be showing is gone.
        index.onRecentlyDeleted = { urls in
            for url in urls { store.forget(fileAt: url) }
        }
    }

    /// Builds the one store the window observes.
    ///
    /// `ZEPHRA_PREVIEW_STATE` short-circuits to a frozen store so the interface can be run and
    /// screenshotted without a model. See `InterfacePreview`.
    private static func makeStore() -> GenerationStore {
        if let frozen = InterfacePreview.store() { return frozen }
        #if DEBUG
        if let exercise = DownloadExercise.makeStore() { return exercise }
        #endif
        let tuning = InferenceTuning.forThisMachine(budget: budget)
        runtime.setCacheLimit(bytes: InferenceTuning.storedCacheLimitBytes())
        runtime.setMemoryLimit(bytes: tuning.memoryLimitBytes)
        runtime.setWiredLimit(bytes: tuning.wiredLimitBytes)
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make)
        registry.register(.qwenImage, QwenImageBackendFactory.make)
        registry.register(.flux2, Flux2BackendFactory.make)
        // The upscaler is registered here for the same reason the backends are: this is the one
        // file that may name a concrete one.
        let store = GenerationStore(
            descriptor: ZephraApp.savedModel(),
            registry: registry,
            outputDirectory: AppSettings.imageLibrary().root,
            locations: AppSettings.modelLocations(),
            upscaler: RealESRGANUpscaler.make,
            runtime: runtime
        )
        store.memoryBudget = budget
        store.weightResidencyPolicy = AppSettings.residencyPolicy(budget: budget)
        store.vaeTilingPolicy = AppSettings.tilingPolicy(budget: budget)
        return store
    }

    /// The model chosen last time, or the largest one this Mac can actually run when nothing
    /// was chosen or the saved identifier belongs to a build that no longer ships that model.
    ///
    /// A saved choice is honoured whatever its size: a model that pages at its default size
    /// still runs at a smaller one, and that is the user's call to make. Whether it is still
    /// on the disk is the store's to find out, at bootstrap, from the backend.
    private static func savedModel() -> ModelDescriptor {
        let saved = UserDefaults.standard.string(forKey: AppSettings.selectedModelID)
        return saved.flatMap(ModelCatalog.descriptor(id:))
            ?? ModelCatalog.default(fitting: budget)
    }
}
