import SwiftUI
import ZephraBackendFlux2
import ZephraBackendLTX2
import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore
import ZephraEngine
import ZephraUpscaleRealESRGAN

/// The composition root. The only place that builds a store, and the only place allowed to
/// know which backend it is built on.
@main
struct ZephraApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var termination
    // Not private: `ZephraApp+Library.swift` wires these four together once the window is up.
    @State var store = ZephraApp.makeStore()
    @State private var cache = ImageCache()
    @State var workspace = InterfacePreview.workspace() ?? WorkspaceSelection()
    @State var index = InterfacePreview.index() ?? LibraryIndex(library: AppSettings.imageLibrary())
    @State var thumbnails = ThumbnailCache()
    /// What the models occupy on disk, for Settings > Models. Built here with the store so the
    /// window and Settings observe the one list.
    @State private var inventory = ModelInventory(locations: AppSettings.modelLocations())
    /// Every `ZEPHRA_*` switch the inference path honours, read from the process environment
    /// here and nowhere else, then handed to the backends as a value.
    private static let environment = InferenceEnvironment.read(ProcessInfo.processInfo.environment)
    /// The GPU runtime the Performance tab reads and tunes, over every backend at once. Built
    /// here because this is the only file allowed to name a backend.
    private static let runtime = CombinedInferenceRuntime([
        ZImageBackendFactory.runtime,
        QwenImageBackendFactory.runtime,
        Flux2BackendFactory.runtime,
        LTX2BackendFactory.runtime,
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
                // The floor under the window, so dragging it narrower or shorter cannot crush
                // the sidebar and the inspector down to nothing between them. A bare
                // `.frame(minWidth:minHeight:)` on the scene's content is not the trap that bit
                // Settings: that was `.windowResizability(.contentSize)` taking the content's
                // *maximum* as the window's, compounded by a `TabView` whose per-tab state
                // stripped the resizable flag back off (`SettingsWindowFrame`). Neither applies
                // here — nothing below calls `.windowResizability`, and `RootView` has no
                // comparable per-tab churn — so the window stays freely resizable and
                // maximisable above the floor.
                //
                // width = 240 (`WorkspaceSplitView`'s own sidebar minimum) + 584 (the canvas
                //   pane's own least-useful width: `PromptEditor`'s preview width of 420 — the
                //   same figure as its measured `restingHeight` of 76, so a considered number —
                //   beside `ReferenceImageWell`'s real 64-point frame, across `PromptRow`'s real
                //   12-point spacing, inside `PromptCapsule`'s 16-point-a-side padding, inside
                //   `CanvasOverlay`'s 28-point-a-side `horizontalPadding`: 420+64+12+2×16+2×28.
                //   The library pane needs less — two columns of `ThumbnailSize.medium` (192)
                //   plus `LibraryGrid`'s own gutters is only 308 — so the canvas figure binds.)
                //   + 320 (`WorkspaceDetail.inspectorWidth`) + 2 (the two hairline dividers
                //   `NavigationSplitView` and `WorkspaceDetail`'s `HStack` each draw) = 1146.
                // height = 52 (the unified toolbar strip with the title and subtitle both
                //   showing, measured with Accessibility against the real window: `AXToolbar`'s
                //   own reported height) + 238 (the prompt capsule and the floating overlay's
                //   trailing margin below it, measured the same way at two different window
                //   widths and matching to the point both times) + 400 (the least a picture
                //   needs to read as a picture and not a strip — this app's own figure twice
                //   over, since `LibraryEmptyState` and `CanvasEmptyState` each settled on a
                //   400-point preview height independently) = 690.
                // Both are under the 1200x840 the window opens at, so the floor only bites on a
                // drag down, never on an ordinary launch. It is the worst case, sidebar and
                // inspector both showing, not the least ever needed — hiding either
                // (Control-Command-S, the inspector toggle) leaves this static floor unable to
                // shrink to match, which is the safe side of that tradeoff: a hidden-chrome
                // window is left with more room than it strictly needs, and 1146x690 is still an
                // ordinary size to be stuck at, not a crushed one.
                .frame(minWidth: 1146, minHeight: 690)
                // Every `@AppStorage` in the window binds through the one store, which is
                // `UserDefaults.standard` for an ordinary launch and a throwaway suite under
                // `FreshStart`; Settings takes it too, below.
                .defaultAppStorage(AppSettings.store)
                .modifier(SeedFormatPreference())
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
                // launch opens on; and `rememberedModel` rather than `descriptor`, so a model
                // only looked at through a picture on the sidebar, never loaded, is not. The
                // tiled decode is not decided here: the store chooses it for each run's own
                // model as the run starts; see `GenerationStore+Tiling`.
                .onChange(of: store.rememberedModel, initial: true) { _, model in
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
        // A session that quit with the window closed used to restore it closed, and a
        // launch with no window and nothing to click but the Dock is not a launch: the one
        // window is presented on every launch whatever the last session left behind.
        .defaultLaunchBehavior(.presented)
        .windowToolbarStyle(.unified)
        .commands {
            ZephraCommands(store: store, workspace: workspace)
            WorkspaceCommands(workspace: workspace, store: store)
            LibraryCommands(workspace: workspace)
            ThumbnailSizeCommands()
            AboutCommands()
            HelpCommands()
        }

        Settings {
            SettingsView()
                .defaultAppStorage(AppSettings.store)
                .environment(store)
                .environment(inventory)
                .environment(index)
                .environment(\.inferenceRuntime, runtime)
                .environment(\.memoryBudget, Self.budget)
                .environment(\.weightResidencyOverride, Self.environment.weightResidency)
        }
        // Deliberately no `.windowResizability`: every content-driven value is re-imposed on
        // the window whenever a tab's state changes — the Models tab's inventory refresh is
        // one — and each re-imposition took the resizable flag off again. The content is
        // flexible in both axes (`SettingsView`), which is what leaves the window resizable,
        // and `SettingsWindowFrame` inside the view owns the floor, the opening size and the
        // centring, which the scene cannot say.

        AboutScenes()
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
        let tuning = InferenceTuning.forThisMachine(
            budget: budget, wiredLimitOverride: environment.wiredLimitBytes)
        runtime.setCacheLimit(bytes: InferenceTuning.storedCacheLimitBytes())
        runtime.setMemoryLimit(bytes: tuning.memoryLimitBytes)
        runtime.setWiredLimit(bytes: tuning.wiredLimitBytes)
        // The tile each run decodes at is chosen by the store as the run starts; this is only
        // what the Performance tab reads before the first run.
        runtime.setVAETileSize(environment.vaeTile)
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make(environment))
        registry.register(.qwenImage, QwenImageBackendFactory.make(environment))
        registry.register(.flux2, Flux2BackendFactory.make(environment))
        registry.register(.ltx2, LTX2BackendFactory.make(environment))
        // The upscaler is registered here for the same reason the backends are: this is the one
        // file that may name a concrete one.
        let store = GenerationStore(
            descriptor: ZephraApp.savedModel(fitting: budget),
            registry: registry,
            outputDirectory: AppSettings.imageLibrary().root,
            locations: AppSettings.modelLocations(),
            upscaler: RealESRGANUpscaler.make,
            runtime: runtime
        )
        store.memoryBudget = budget
        store.weightResidencyPolicy = AppSettings.residencyPolicy(
            budget: budget, override: environment.weightResidency)
        store.vaeTilingPolicy = AppSettings.tilingPolicy(budget: budget)
        return store
    }
}
