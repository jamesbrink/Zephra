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
        }
    }

    /// Builds the one store the window observes.
    ///
    /// `ZEPHRA_PREVIEW_STATE` short-circuits to a frozen store so the interface can be run and
    /// screenshotted without a model. See `InterfacePreview`.
    private static func makeStore() -> GenerationStore {
        if let frozen = InterfacePreview.store() { return frozen }
        let tuning = InferenceTuning.forThisMachine()
        ZImageRuntime.configure(
            cacheLimitBytes: tuning.cacheLimitBytes,
            memoryLimitBytes: tuning.memoryLimitBytes
        )
        return GenerationStore(backendFactory: ZImageBackendFactory.make)
    }
}
