import SwiftUI
import ZephraBackendFlux2
import ZephraBackendLTX2
import ZephraBackendQwenImage21
import ZephraBackendWan
import ZephraBackendZImage
import ZephraCore
import ZephraEngine
import ZephraLinkHost
import ZephraMedia
import ZephraUpscaleRealESRGAN

/// The composition root. The only place that builds a store, and the only place allowed to
/// know which backend it is built on.
@main
struct ZephraApp: App {
    // Not private: `ZephraApp+Library.swift` hands it what a clicked notification means.
    @NSApplicationDelegateAdaptor(AppLifecycle.self) var termination
    // Not private: `ZephraApp+Library.swift` wires these four together once the window is up.
    @State var store = ZephraApp.makeStore()
    @State private var cache = ImageCache()
    @State var workspace = InterfacePreview.workspace() ?? WorkspaceSelection()
    @State var index = InterfacePreview.index() ?? LibraryIndex(library: AppSettings.imageLibrary())
    @State var thumbnails = ThumbnailCache()
    /// Whether the window opens on the first-launch model chooser. Built here with everything
    /// else the window observes, and resolved from the preference synchronously, so a launch
    /// that has never chosen a model opens on the chooser rather than flashing the canvas.
    @State private var welcome = WelcomeGate()
    /// What the models occupy on disk, for Settings > Models. Built here with the store so the
    /// window and Settings observe the one list.
    @State private var inventory = ModelInventory(locations: AppSettings.modelLocations())
    /// The link a paired iPhone talks to this Mac over, built in `.task` beside the library's
    /// wiring rather than here, since it takes the store, the index and the thumbnail folder
    /// and a `@State` initializer cannot read another. Nil until then, and on a preview build;
    /// `ZephraApp+Companion.swift` is the whole of it.
    @State var companion: CompanionHost?
    /// The watch on the GPU, built in `.task` beside the companion it sits alongside and for the
    /// same reason: it reads the store, which a `@State` initialiser cannot. Not private, because
    /// `ZephraApp+DeviceLoss.swift` is the half that builds and starts it.
    @State var lossWatch: DeviceLossWatch?
    /// Whether a newer Zephra has been published, and how far along installing it is. Built
    /// here with everything else the window observes, and never a singleton; a frozen
    /// `ZEPHRA_PREVIEW_STATE=update` build gets one standing still, with no timer under it.
    @State var updates = InterfacePreview.updates() ?? UpdateChecker()
    /// The roads that link listens on, and the port the local one actually took. Built here
    /// with nothing in it, since which roads it opens is the preference's answer rather than
    /// this launch's.
    @State var roads = CompanionRoads()
    /// The two companion switches, read here so the roads follow them. An explicit store
    /// because `defaultAppStorage` is a view modifier and this is the scene above the views,
    /// and a fresh start must read its own suite rather than the person's.
    @AppStorage(AppSettings.companionEnabled, store: AppSettings.store)
    private var companionEnabled = AppSettings.initialCompanionEnabled
    @AppStorage(AppSettings.companionRelayEnabled, store: AppSettings.store)
    private var companionRelayEnabled = AppSettings.initialCompanionRelayEnabled
    /// The three load preferences, read here so the store follows them while the app runs. An
    /// explicit store for the reason the companion switches take one: this is the scene above
    /// the views, where `defaultAppStorage` has not been applied.
    @AppStorage(AppSettings.loadModelsAutomatically, store: AppSettings.store)
    private var loadModelsAutomatically = AppSettings.initialLoadModelsAutomatically
    @AppStorage(AppSettings.idleUnloadMinutes, store: AppSettings.store)
    private var idleUnloadMinutes = AppSettings.initialIdleUnloadMinutes
    @AppStorage(AppSettings.warmUpOnLaunch, store: AppSettings.store)
    private var warmUpOnLaunch = AppSettings.initialWarmUpOnLaunch
    /// The Live preview cadence, followed the way the load preferences are.
    @AppStorage(AppSettings.livePreview, store: AppSettings.store)
    private var livePreview = AppSettings.initialLivePreview
    /// Every `ZEPHRA_*` switch the inference path honours, read from the process environment
    /// here and nowhere else, then handed to the backends as a value.
    private static let environment = InferenceEnvironment.read(ProcessInfo.processInfo.environment)
    /// The GPU runtime the Performance tab reads and tunes, over every backend at once. Built
    /// here because this is the only file allowed to name a backend.
    private static let runtime = CombinedInferenceRuntime([
        ZImageBackendFactory.runtime,
        Flux2BackendFactory.runtime,
        LTX2BackendFactory.runtime,
        QwenImage21BackendFactory.runtime,
        WanBackendFactory.runtime,
    ])
    private var runtime: CombinedInferenceRuntime { Self.runtime }
    /// What this Mac's GPU may keep resident, read once here from the runtime and the
    /// `iogpu.wired_limit_mb` sysctl, then handed to every view and to the store: the model
    /// picker's wording, the tiled decode, and the fallback model all follow it.
    // A frozen screenshot build may state the Mac it is pretending to be, so the chooser can be
    // photographed as a 16 GB Mac sees it; every other launch asks this Mac's own GPU. A Debug
    // launch may then replace that working set with another Mac's
    // (`ZEPHRA_GPU_WORKING_SET_MB`), so a hand check meant for a 16 GB Mac can be run on the
    // Mac at hand; this is the one place that variable is read.
    private static let budget = GPUWorkingSetOverride.replacing(
        InterfacePreview.budget() ?? GPUMemoryBudget.forThisMachine(runtime: runtime),
        environment: ProcessInfo.processInfo.environment)

    var body: some Scene {
        // One window, not a group: everything a window would own is app-wide state built
        // above, so a second one could only mirror the first. `Window` reopens on a Dock
        // click and lists itself under the Window menu; see ROADMAP for per-window state.
        Window("Zephra", id: "main") {
            WelcomeHost()
                // The floor under the window, so dragging it in cannot crush the panes to
                // nothing between the sidebar and the inspector. A bare
                // `.frame(minWidth:minHeight:)` on the scene's content is not the trap that bit
                // Settings: that was `.windowResizability(.contentSize)` taking the content's
                // *maximum* as the window's, compounded by a `TabView` whose per-tab state
                // stripped the resizable flag back off (`SettingsWindowFrame`). Neither applies
                // here, so the window stays freely resizable and maximisable above the floor.
                //
                // The figure is what the window may be *dragged to*, which is not what a
                // comfortable three-column layout wants — the same distinction Settings needed
                // between `openingHeight` and `minimumHeight`, and for the same reason. A floor
                // built from the full layout came to 1146x690 (240 sidebar + 584 canvas pane +
                // 320 inspector + 2 dividers, and 52 toolbar + 238 capsule + 400 picture), and
                // a minimum that large cannot fit a supported Mac running a larger-text scaled
                // resolution such as 1024x640 — the window could then never be made to fit its
                // own screen, controls stranded off the edge, which is worse than a cramped
                // pane and is exactly the bug the Settings floor had.
                //
                // So the floor is the least the window is still *usable* at, and it leans on
                // the two pieces of chrome a person can put away: 240 (`WorkspaceSplitView`'s
                // sidebar minimum) + 320 (`WorkspaceDetail.inspectorWidth`) + 320 for the pane
                // between them, which is a shade over the library's own measured floor of 308
                // — two columns of `ThumbnailSize.medium` (192) plus `LibraryGrid`'s gutters.
                // The canvas pane wants 584 to lay its prompt capsule out properly and does not
                // get it here; at the floor the answer is Control-Command-S or the inspector
                // toggle, either of which hands the pane 320 points back. Height is the
                // measured 52-point toolbar strip plus the measured 238-point capsule and its
                // margin, leaving 270 of picture — less than the 400 an empty state wants, and
                // still a picture rather than a strip.
                //
                // 880x560 fits a 1024x640 screen with its menu bar removed, and sits well under
                // the 1200x840 the window opens at, so the floor only bites on a drag down.
                .frame(minWidth: 880, minHeight: 560)
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
                .environment(welcome)
                .environment(updates)
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
                    // Not while the first-launch chooser is up: nothing has been chosen yet,
                    // and writing the catalog's fallback here would make quitting on that
                    // screen look, next launch, exactly like having answered it.
                    guard !welcome.isShowing else { return }
                    AppSettings.write(model.id, to: AppSettings.selectedModelID)
                }
                // The answer itself, for the case the line above cannot see: a chooser
                // answered with the model the store was already pointing at moves nothing, so
                // nothing would ever be written for that session. Still one writer.
                // The roads follow the two switches, which live in Settings, a scene of its own
                // that cannot reach the composition root's state. Both call the same one door.
                // The three load preferences, set on the store here and followed here, so a
                // change in Settings applies to the next choice rather than to the next
                // launch. Every door into a load used to re-read the warm-up flag for itself,
                // which is four readers of one preference; one writer is the rule the two new
                // ones follow from the start.
                .onChange(of: loadModelsAutomatically, initial: true) { _, _ in
                    store.loadingMode = AppSettings.loadingMode()
                }
                .onChange(of: idleUnloadMinutes, initial: true) { _, _ in
                    store.idleUnloadDelay = AppSettings.idleUnloadDelay()
                }
                .onChange(of: warmUpOnLaunch, initial: true) { _, warms in
                    store.warmsUpAfterLoad = warms
                }
                .onChange(of: livePreview, initial: true) { _, cadence in
                    store.previewCadence = cadence
                }
                .onChange(of: companionEnabled) { _, _ in openCompanionRoads() }
                .onChange(of: companionRelayEnabled) { _, _ in openCompanionRoads() }
                .onChange(of: welcome.isShowing) { _, showing in
                    guard !showing else { return }
                    AppSettings.write(store.rememberedModel.id, to: AppSettings.selectedModelID)
                }
                .task {
                    // Quit waits for a swap in flight: between the rename and the end of
                    // `ditto` there is no Zephra where there was one.
                    termination.isInstalling = { updates.isInstalling }
                    termination.shutdown = {
                        // The link first: a phone holding a request open is the one reader that
                        // could still ask the store for work while it is trying to finish.
                        await stopCompanion()
                        // Store next: its last save calls `onImageSaved` -> `index.insert`,
                        // which must land before the index stops taking anything.
                        await store.shutdown()
                        await index.shutdown()
                        // Not over a lost GPU: a synchronize is one more command buffer into a
                        // channel the driver is refusing, and there is nothing left in flight
                        // to drain — the store submitted nothing after the loss.
                        guard !store.deviceLost else { return }
                        let runtime = Self.runtime
                        await Task.detached { runtime.synchronize() }.value
                    }
                    openLibrary()
                    startUpdates()
                    // The GPU's loss is caught from here rather than from a view, so a window
                    // that stays shut is not a Mac that never learns of it; `DeviceLossWatch`.
                    startDeviceLossWatch()
                    // After the library, so the saved and deleted closures it sets are wrapped
                    // rather than replaced.
                    await startCompanion()
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
            ModelCommands(store: store, workspace: workspace, welcome: welcome)
            WorkspaceCommands(workspace: workspace, store: store)
            LibraryCommands(workspace: workspace)
            ThumbnailSizeCommands()
            AboutCommands()
            UpdateCommands(updates: updates)
            HelpCommands()
        }

        Settings {
            SettingsView()
                .defaultAppStorage(AppSettings.store)
                .environment(store)
                .environment(inventory)
                .environment(index)
                // Optional on purpose: Settings can be opened on a preview build, which has no
                // link, and the Companion tab draws the "not available" case from the absence.
                .environment(companion)
                .environment(updates)
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
        // First, before anything reads the device. `Self.budget` asks the GPU what it may keep
        // resident, which is a call into the runtime like any other: with no handler of its
        // own, an MLX error raised there — or anywhere else outside a run's own device-error
        // boundary — ends the process.
        runtime.installDeviceErrorLogging()
        if let frozen = InterfacePreview.store() {
            // The same figure the views are handed, or a frozen build would grey its cards
            // against one Mac and answer `canSelect` about another.
            frozen.memoryBudget = budget
            return frozen
        }
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
        registry.register(.flux2, Flux2BackendFactory.make(environment))
        registry.register(.ltx2, LTX2BackendFactory.make(environment))
        registry.register(.qwenImage21, QwenImage21BackendFactory.make(environment))
        registry.register(.wan, WanBackendFactory.make(environment))
        // The upscaler is registered here for the same reason the backends are: this is the one
        // file that may name a concrete one.
        let store = GenerationStore(
            descriptor: ZephraApp.savedModel(fitting: budget),
            registry: registry,
            outputDirectory: AppSettings.imageLibrary().root,
            locations: AppSettings.modelLocations(),
            upscaler: RealESRGANUpscaler.make,
            runtime: runtime,
            // Reads a clip's tail and joins clips, for Extend Clip; injected here for the
            // reason the upscaler is, so the engine names no media code.
            clips: MP4Stitcher(),
            // What the Mac has free, asked of the kernel before every load and run. Injected
            // for the reason the runtime is: the engine must answer the same way under test
            // as it does here, and only this layer may make a host call.
            machineMemory: HostMachineMemory()
        )
        store.memoryBudget = budget
        store.weightResidencyPolicy = AppSettings.residencyPolicy(
            budget: budget, override: environment.weightResidency)
        store.vaeTilingPolicy = AppSettings.tilingPolicy(budget: budget)
        // Before `bootstrap()`, which reads it: under on-demand the launch surveys the disk
        // and loads nothing. The scene's `onChange` keeps all three following the preferences
        // from there.
        store.loadingMode = AppSettings.loadingMode()
        store.idleUnloadDelay = AppSettings.idleUnloadDelay()
        store.warmsUpAfterLoad = AppSettings.flag(AppSettings.warmUpOnLaunch)
        store.previewCadence = AppSettings.previewCadence()
        return store
    }
}
