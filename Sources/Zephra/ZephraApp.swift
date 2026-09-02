import SwiftUI
import ZephraBackendZImage
import ZephraCore
import ZephraEngine

/// The composition root. The only place that builds a store, and the only place allowed to
/// know which backend it is built on.
@main
struct ZephraApp: App {
    @State private var store = ZephraApp.makeStore()
    @State private var cache = ImageCache()
    /// The GPU runtime the Performance tab reads and tunes. Built here because this is the only
    /// file allowed to name a backend.
    private let runtime = ZImageInferenceRuntime()

    var body: some Scene {
        WindowGroup("Zephra") {
            RootView()
                .environment(store)
                .environment(cache)
        }
        .defaultSize(width: 1200, height: 840)
        .windowToolbarStyle(.unified)
        .commands { ZephraCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
                .environment(\.inferenceRuntime, runtime)
        }
    }

    /// Builds the one store the window observes.
    ///
    /// `ZEPHRA_PREVIEW_STATE` short-circuits to a frozen store so the interface can be run and
    /// screenshotted without a model. See `InterfacePreview`.
    private static func makeStore() -> GenerationStore {
        if let frozen = InterfacePreview.store() { return frozen }
        ZImageRuntime.configure(
            cacheLimitBytes: InferenceTuning.storedCacheLimitBytes(),
            memoryLimitBytes: InferenceTuning.forThisMachine().memoryLimitBytes
        )
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make)
        return GenerationStore(descriptor: ZephraApp.savedModel(), registry: registry)
    }

    /// The model chosen last time, or the catalog's default when nothing was chosen or the
    /// saved identifier belongs to a build that no longer ships that model.
    private static func savedModel() -> ModelDescriptor {
        let saved = UserDefaults.standard.string(forKey: AppSettings.selectedModelID)
        return saved.flatMap(ModelCatalog.descriptor(id:)) ?? ModelCatalog.default
    }
}
