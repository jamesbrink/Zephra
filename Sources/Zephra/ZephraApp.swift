import SwiftUI
import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore
import ZephraEngine

/// The composition root. The only place that builds a store, and the only place allowed to
/// know which backend it is built on.
@main
struct ZephraApp: App {
    @State private var store = ZephraApp.makeStore()
    @State private var cache = ImageCache()
    @State private var workspace = InterfacePreview.workspace() ?? WorkspaceSelection()
    @State private var index = InterfacePreview.index() ?? LibraryIndex(library: .pictures())
    @State private var thumbnails = ThumbnailCache()
    /// The GPU runtime the Performance tab reads and tunes, over every backend at once. Built
    /// here because this is the only file allowed to name a backend.
    private static let runtime = CombinedInferenceRuntime([
        ZImageInferenceRuntime(),
        QwenImageInferenceRuntime(),
    ])
    private var runtime: CombinedInferenceRuntime { Self.runtime }

    var body: some Scene {
        WindowGroup("Zephra") {
            RootView()
                .environment(store)
                .environment(cache)
                .environment(workspace)
                .environment(index)
                .environment(thumbnails)
                // The tiled decode is chosen for the model that is about to run, so the answer
                // is worked out again whenever the model changes. Settings re-applies it when
                // the preference itself changes; see `VAETilingControl`.
                .onChange(of: store.descriptor, initial: true) { _, model in
                    runtime.setVAETileSize(AppSettings.tilingPolicy().tileSize(for: model))
                }
                .task { openLibrary() }
        }
        .defaultSize(width: 1200, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            ZephraCommands(store: store)
            WorkspaceCommands(workspace: workspace)
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(\.inferenceRuntime, runtime)
        }
    }

    /// Starts the library reading the folder, and tells it about the images this session makes
    /// and unmakes. Idempotent, which is what lets a second window call it too.
    ///
    /// A saved image is handed to the index by path, one header read and a sorted insert; a
    /// deleted one is a rescan, because the store deletes to the system Trash and a path that
    /// has gone is not something the index can be told about in place. Either way the folder
    /// watch would notice in its own time — this is only so the grid moves at once.
    private func openLibrary() {
        index.start()
        thumbnails.sweep()
        store.onImageSaved = { url in index.insert(fileAt: url) }
        store.onImageDeleted = { _ in Task { await index.rescanNow() } }
    }

    /// Builds the one store the window observes.
    ///
    /// `ZEPHRA_PREVIEW_STATE` short-circuits to a frozen store so the interface can be run and
    /// screenshotted without a model. See `InterfacePreview`.
    private static func makeStore() -> GenerationStore {
        if let frozen = InterfacePreview.store() { return frozen }
        runtime.setCacheLimit(bytes: InferenceTuning.storedCacheLimitBytes())
        runtime.setMemoryLimit(bytes: InferenceTuning.forThisMachine().memoryLimitBytes)
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make)
        registry.register(.qwenImage, QwenImageBackendFactory.make)
        return GenerationStore(descriptor: ZephraApp.savedModel(), registry: registry)
    }

    /// The model chosen last time, or the largest one this Mac can actually run when nothing
    /// was chosen or the saved identifier belongs to a build that no longer ships that model.
    ///
    /// A saved choice is honoured whatever its size: a model that pages at its default size
    /// still runs at a smaller one, and that is the user's call to make.
    private static func savedModel() -> ModelDescriptor {
        let saved = UserDefaults.standard.string(forKey: AppSettings.selectedModelID)
        return saved.flatMap(ModelCatalog.descriptor(id:))
            ?? ModelCatalog.default(fitting: ProcessInfo.processInfo.physicalMemory)
    }
}
