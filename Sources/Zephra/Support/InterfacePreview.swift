import Foundation
import ZephraCore
import ZephraEngine

/// Launches the app frozen in one engine state, with no model and no network, so the
/// interface can be screenshotted and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `ready`, `image`, `editing`, `tucked`, `generating`, `starting`,
/// `queued`, `watching`, `batch`, `library`, `viewer`, `picker`, `downloading`, `building`, or `failed`
/// before launching. `settings` uses the configured library on disk with a frozen engine for
/// folder-change UAT; point `imagesDirectory` at a temporary fixture first. Debug builds only; in Release this is inert.
///
/// This half is what the composition root calls. `InterfacePreview+Frozen.swift` is how each
/// state is stood up.
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
        case "generating", "starting", "queued", "watching":
            return runningStore(state: state, seeds: name == "queued" ? 3 : 2)
        default:
            // The editing and picker previews run against an invented model that reads a
            // reference, so the well beside the prompt is there to be screenshotted.
            let descriptor = isEditingBuild ? PreviewModel.editing : ModelCatalog.default
            let store = GenerationStore.preview(
                state: state, image: frozenImage(for: state), descriptor: descriptor,
                swappingModel: name == "downloading")
            if isEditingBuild {
                // Through the same door the interface uses, so the frozen window shows the
                // strength a dropped picture really gets rather than the 1 that means none.
                store.useAsReference(PreviewImages.referencePNG())
            }
            return store
        }
    }

    /// Whether this build wants a reference-capable model standing up: `editing`, to
    /// screenshot the filled well, and `picker`, which forces its sheet open over the same well.
    static var isEditingBuild: Bool { name == "editing" || name == "picker" }

    /// Whether the frozen window should force its reference picker sheet open. The well's own
    /// `@State` cannot be reached from the composition root the way `workspace.viewing` can, so
    /// the well reads this itself on appear rather than being handed a value from above.
    static var wantsReferencePicker: Bool {
        #if DEBUG
        name == "picker"
        #else
        false
        #endif
    }

    /// Where the frozen window is looking. Stated rather than restored, so a screenshot build
    /// shows the same thing on every machine.
    static func workspace() -> WorkspaceSelection? {
        guard requestedState != nil else { return nil }
        let workspace = WorkspaceSelection(pane: name == "library" || name == "viewer" ? .library : .canvas)
        // `tucked` exists to photograph the lip, so the window has to actually be tucked when
        // the screenshot is taken rather than reaching that state through a simulated click.
        if name == "tucked" { workspace.promptTucked = true }
        return workspace
    }

    /// The one item the frozen `viewer` window shows full size, or nil otherwise.
    ///
    /// `workspace()` cannot answer this itself: it and `index()` are called independently and
    /// each builds its own `LibraryIndex.preview`, over its own temporary files, so only the
    /// index that actually ends up in the window knows which id its first item got. The
    /// composition root calls this once both exist, after `index.start()`.
    static func viewing(in index: LibraryIndex) -> LibraryItem.ID? {
        guard requestedState != nil, name == "viewer" else { return nil }
        return index.sections.first?.items.first?.id
    }

    /// A library with no folder behind it, or nil for a normal launch. Nothing in it is read
    /// from or written to a disk, so a frozen window shows a full grid on a machine that has
    /// never generated anything.
    static func index() -> LibraryIndex? {
        guard requestedState != nil else { return nil }
        if name == "settings" { return LibraryIndex(library: AppSettings.imageLibrary()) }
        // Real files in the temporary directory, so the grid shows pictures. The index itself
        // still touches no disk: it is handed the paths and never looks for a folder.
        return LibraryIndex.preview(count: 38, pictures: PreviewImages.libraryFiles(count: 41))
    }

    /// A run of `count` seeds of one prompt, the first of which is the one being rendered.
    /// Shared with the `#Preview`s of the queue, so the frozen window and the previews of its
    /// parts are showing the same thing.
    static func queuedRun(of count: Int = 3, steps: Int = 4) -> [QueuedGeneration] {
        let batch = UUID()
        let settings = GenerationSettings(
            prompt: "a red bicycle against a limestone wall",
            size: ImageSize(width: 1024, height: 1024),
            steps: steps,
            guidance: 0,
            seed: 8_123_447_209_115_662
        )
        return (0..<count).map { index in
            var seeded = settings
            seeded.seed &+= UInt64(index)
            return QueuedGeneration(
                model: ModelCatalog.default,
                settings: seeded,
                batchID: batch,
                batchIndex: index
            )
        }
    }
}
