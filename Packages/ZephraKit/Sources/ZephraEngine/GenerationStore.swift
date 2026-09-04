import Foundation
import Observation
import ZephraCore
import os

/// The single object the UI observes. Owns the engine's state and the images it produced.
@MainActor
@Observable
public final class GenerationStore {
    /// What the engine is doing right now.
    public internal(set) var state: EngineState = .idle
    /// The image shown on the canvas.
    public internal(set) var current: GeneratedImage?
    /// This session's images, newest first, capped at 24. What was made before this launch is
    /// the library's business, not the store's: `LibraryIndex` reads the folder.
    public internal(set) var history: [GeneratedImage] = []
    /// What the next generation will use. Edited directly by the UI.
    public var settings: GenerationSettings
    /// The model the next generation will use. Change it with `switchModel(to:)`; queued
    /// generations keep the model they were queued for.
    public internal(set) var descriptor: ModelDescriptor
    /// What is on disk for each known model, by descriptor id. Filled in at bootstrap and after
    /// every load; a model missing from the map has not been looked at yet.
    public internal(set) var availability: [ModelDescriptor.ID: ModelAvailability] = [:]
    /// Wall-clock time of the last completed generation.
    public internal(set) var lastDuration: Duration?
    /// The most recent image that could not be written, or nil when the last one saved. Shown
    /// as a notice; it never stops the engine or the queue.
    public internal(set) var lastSaveFailure: SaveFailure?
    /// Generations waiting their turn, oldest first. Runs down by itself after each image.
    public internal(set) var queue: [QueuedGeneration] = []
    /// The generation being rendered right now, or nil when none is. It is not in `queue`: the
    /// queue is what is still waiting, and a list showing both reads it straight off.
    public internal(set) var running: QueuedGeneration?
    /// Whether the canvas is following the generation in flight rather than showing a picture
    /// the user chose. See `GenerationStore+FollowingRun.swift`, which is where every rule
    /// about it lives; it is stored here only because Swift keeps stored properties on the
    /// type. `internal(set)` for the same reason: the extension has to be able to set it.
    public internal(set) var followsRun = false
    /// The newest frame of the generation in flight, or nil when there is none to show — before
    /// the first frame of a run, and from the moment any run ends.
    public internal(set) var livePreview: GenerationPreview?
    /// The model whose weights are resident right now, or nil while none are. It trails
    /// `descriptor` whenever a switch is waiting for the queue to drain.
    public internal(set) var loadedDescriptor: ModelDescriptor?
    /// True while the engine is between queued generations, swapping to the model the next one
    /// needs. The queue accepts more work throughout.
    public internal(set) var isSwitchingForQueue = false
    /// True from the moment a model swap is asked for until the new model has loaded or the
    /// swap was stopped. While it is true the state passes through `.idle` without meaning
    /// "nothing to do", so nothing else may start a load.
    public internal(set) var isSwappingModel = false
    /// Called with the file an image was just written to, once it is on disk. The app hands the
    /// library index a way to add that one file rather than rescanning the folder for it; the
    /// engine has no idea an index exists.
    public var onImageSaved: (@MainActor (URL) -> Void)?
    /// Called with the file an image was moved out of when it was deleted from the filmstrip, so
    /// the app can tell the library index about it without waiting for a folder watch.
    public var onImageDeleted: (@MainActor (URL) -> Void)?
    /// The most recent thing the library could not do for this store — an image that could not
    /// be opened, so far — or nil when the last one worked.
    public internal(set) var lastLibraryFailure: LibraryFailure?
    /// Whether a load ends with a throwaway generation that pays the kernel-compilation cost
    /// up front. The engine has no idea where the answer comes from; the app sets it from the
    /// user's preference before it calls `bootstrap()`.
    public var warmsUpAfterLoad = true

    /// How many images stay in memory before the oldest is dropped.
    static let historyLimit = 24

    // Machinery, not surface. These are internal rather than private only so the generation
    // half of this type, in GenerationStore+Generation.swift, can reach them.
    /// Which backend runs which model family, or nil for a preview store, which has none and so
    /// never loads, generates, or reaches a model at all.
    let registry: BackendRegistry?
    /// How to build the one upscaler, or nil for a build that carries none — a preview store,
    /// or a tool. Nil is what greys every Upscale button, with no other rule needed.
    let upscalerFactory: UpscalerFactory?
    let library: ImageLibrary
    let logger = Logger(subsystem: "io.zephra", category: "engine")

    @ObservationIgnored var inference: InferenceActor?
    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var switchTask: Task<Void, Never>?
    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var libraryTask: Task<Void, Never>?
    @ObservationIgnored var openTask: Task<Void, Never>?
    @ObservationIgnored var upscaleTask: Task<Void, Never>?

    /// Creates a store for one model, running on the backends `registry` knows how to build.
    /// `outputDirectory` nil means ~/Pictures/Zephra.
    public convenience init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        registry: BackendRegistry,
        outputDirectory: URL? = nil,
        upscaler: UpscalerFactory? = nil
    ) {
        self.init(
            descriptor: descriptor, registry: registry, output: outputDirectory,
            upscaler: upscaler)
    }

    /// The one designated initializer. A nil `registry` makes a preview store: see
    /// `GenerationStore+Preview.swift`.
    init(
        descriptor: ModelDescriptor, registry: BackendRegistry?, output: URL?,
        upscaler: UpscalerFactory? = nil
    ) {
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.registry = registry
        self.upscalerFactory = upscaler
        self.library = output.map { ImageLibrary(root: $0) } ?? .pictures()
    }

    /// The folder finished images are written to. The one answer to that question: nothing
    /// else works the path out for itself.
    public var outputDirectory: URL { library.root }

    /// True when a generation can start right now: the engine is ready and there is a prompt.
    public var canGenerate: Bool { state.acceptsGeneration && settings.isReadyToGenerate }

    /// True when `generate()` will do something: start now, or queue behind the running one.
    public var canQueue: Bool { settings.isReadyToGenerate && (state.acceptsGeneration || isDraining) }

    /// Shows an earlier image on the canvas and adopts its settings, so the obvious next move
    /// is to tweak one thing and generate a variation.
    public func select(_ image: GeneratedImage) {
        stopFollowingRun()
        current = image
        settings = image.settings
        // Everything else carries over whichever model made it; a picture to edit does not,
        // on a model that cannot read one, or the well could neither show it nor clear it.
        if !descriptor.capabilities.supportsReferenceImage {
            settings.referenceImage = nil
        }
    }

    /// Picks a fresh seed for the next generation.
    public func randomizeSeed() { settings = settings.withRandomSeed() }

    /// Waits for everything this store has in flight. A seam for tests, which need generation
    /// and the file write that follows it to be finished before they assert.
    func settle() async {
        await switchTask?.value
        await bootstrapTask?.value
        await generationTask?.value
        // Before the save task: an upscale's write is queued on it as the upscale ends, and
        // this one is nil the moment that has happened.
        await upscaleTask?.value
        await saveTask?.value
        await libraryTask?.value
        await openTask?.value
    }
}
