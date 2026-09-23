import Foundation
import ZephraCore
import ZephraEngine
import ZephraSnapshot

/// Launches the app frozen in one engine state, with no model and no network, so the
/// interface can be screenshotted and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `ready`, `image`, `editing`, `tucked`, `clip`, `generating`,
/// `starting`, `queued`, `watching`, `finishing`, `batch`, `library`, `viewer`, `picker`, `welcome`,
/// `models`, `downloading`, `building`, `update`, or `failed` before launching. `settings` uses the configured library on disk with a frozen engine for
/// folder-change UAT; point `imagesDirectory` at a temporary fixture first. Debug builds only; in Release this is inert.
///
/// This half is what the composition root calls for the store and the flags;
/// `InterfacePreview+Window.swift` states the window and the library around it, and
/// `InterfacePreview+Frozen.swift` is how each state is stood up.
enum InterfacePreview {
    /// A store frozen in the requested state, or nil for a normal launch. The frozen store has
    /// no backend, so `bootstrap()` on it does nothing and no model is ever looked for.
    static func store() -> GenerationStore? {
        guard let state = requestedState else { return nil }
        switch name {
        case "settings":
            return GenerationStore.preview(state: state, outputDirectory: AppSettings.imageLibrary().root)
        case "batch":
            let run = PreviewImages.run(of: 4)
            let store = GenerationStore.preview(state: state, images: run)
            store.settings = run[0].settings
            return store
        case "generating", "starting", "queued", "watching", "finishing":
            return runningStore(state: state, seeds: name == "queued" ? 3 : 2)
        default:
            // The editing, picker and clip previews run against an invented model that reads a
            // reference, so the well beside the prompt is there to be screenshotted.
            let descriptor: ModelDescriptor =
                if isEditingBuild { PreviewModel.editing }
                else if name == "clip" { PreviewModel.video }
                else { ModelCatalog.default }
            let store = GenerationStore.preview(
                state: state, image: frozenImage(for: state), descriptor: descriptor,
                swappingModel: name == "downloading", loaded: loadedModel(for: state, descriptor))
            if isEditingBuild {
                // Through the same door the interface uses, so the frozen window shows the
                // strength a dropped picture really gets rather than the 1 that means none.
                // Two pictures unless `ZEPHRA_PREVIEW_REFERENCES` says otherwise, which is what
                // photographs the strip rather than one tile standing on its own.
                store.useAsReferences(PreviewImages.referencePNGs(count: referenceCount))
            } else if name == "clip" {
                store.useAsReference(PreviewImages.referencePNG())
            }
            return store
        }
    }

    /// The update banner frozen with a release on it, or nil for every other launch. A frozen
    /// checker has no timer and no feed under it, so a screenshot build reaches no network at
    /// all — the same rule `startCompanion` follows.
    static func updates() -> UpdateChecker? {
        guard requestedState != nil, name == "update" else { return nil }
        return UpdateChecker.frozen(.available(ReleaseManifest(
            url: URL(string: "https://zephra-assets.urandom.io/releases/Zephra-0.1.0-202609120231.dmg")!,
            version: "0.1.0", build: "202609120231", sha256: String(repeating: "a", count: 64))))
    }

    /// The model a frozen store says is in memory: the chosen one wherever the engine could
    /// only have reached this state over loaded weights, and nothing otherwise. Without it the
    /// toolbar in a `ready` screenshot would offer to load the model it is already ready on.
    static func loadedModel(for state: EngineState, _ descriptor: ModelDescriptor) -> ModelDescriptor? {
        switch state {
        case .ready, .generating, .warmingUp, .upscaling, .cancelling: descriptor
        case .idle, .checkingModel, .downloading, .building, .loading, .failed: nil
        }
    }

    /// Whether this build wants a reference-capable model standing up: `editing`, to
    /// screenshot the filled well, and `picker`, which forces its sheet open over the same well.
    static var isEditingBuild: Bool { name == "editing" || name == "picker" }

    /// How many pictures the frozen strip holds: two, so a screenshot shows a strip rather than
    /// one tile, and whatever `ZEPHRA_PREVIEW_REFERENCES` says when the point is the scroll past
    /// four. Clamped to what the limits carry, so no number in an environment variable can put
    /// the window in a state the app could not reach.
    ///
    /// A hook of its own rather than another preview state, for the reason `ZEPHRA_VAE_TILE` is
    /// not a state: it is one number inside a state, and `editing10` would be a second state to
    /// keep in step with the first.
    static func referenceCount(in environment: [String: String] = ProcessInfo.processInfo.environment)
        -> Int
    {
        guard let value = environment[referenceCountVariable], let count = Int(value) else {
            return 2
        }
        return min(max(count, 0), ReferenceLimits.maximumPictures)
    }

    static let referenceCountVariable = "ZEPHRA_PREVIEW_REFERENCES"

    private static var referenceCount: Int { referenceCount() }

    /// Whether the frozen window should open on the reference picker. Read by `workspace()`,
    /// which states it the way it states the browser and the tuck: the well no longer holds the
    /// flag itself.
    static var wantsReferencePicker: Bool {
        #if DEBUG
        name == "picker"
        #else
        false
        #endif
    }

    /// Whether the frozen window should open on the first-launch model chooser rather than on
    /// the workspace, whatever this Mac's preferences say. `WelcomeGate` reads it in `init`,
    /// since the chooser has to be up before the first frame rather than raised after it.
    static var wantsWelcome: Bool {
        #if DEBUG
        name == "welcome"
        #else
        false
        #endif
    }

    /// The budget a frozen build measures models against, or nil for a normal launch, which
    /// asks this Mac's own GPU.
    ///
    /// The chooser is drawn entirely out of this figure — which cards are greyed, what each one
    /// says it needs, which is recommended — so photographing it on a 48 GB workstation shows a
    /// screen nobody with a 16 GB Mac ever sees. A screenshot build states the Mac it is
    /// pretending to be, the way it states which pane is up and what the library holds.
    static func budget() -> MemoryBudget? {
        guard requestedState != nil, name == "welcome" || name == "models" else { return nil }
        return MemoryBudget(physicalMemory: 16 << 30)
    }
}
