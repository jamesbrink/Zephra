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
    /// The generation being rendered right now, or nil when none is. Not in `queue`, which is
    /// what is still waiting, so a list showing both reads them straight off.
    public internal(set) var running: QueuedGeneration?
    /// Whether the canvas is following the generation in flight rather than showing a picture
    /// the user chose. Every rule about it is in `GenerationStore+FollowingRun.swift`; it is
    /// stored here only because Swift keeps stored properties on the type.
    public internal(set) var followsRun = false
    /// The newest frame of the generation in flight, or nil when there is none to show — before
    /// the first frame of a run, and from the moment any run ends.
    public internal(set) var livePreview: GenerationPreview?
    /// The model whose weights are resident right now, or nil while none are. It trails
    /// `descriptor` whenever a switch is waiting for the queue to drain.
    public internal(set) var loadedDescriptor: ModelDescriptor?
    /// The directory those weights were read from, so a settings row can tell the one copy
    /// that is in use from a duplicate of the same model elsewhere. Nil while none are.
    public internal(set) var loadedDirectory: URL?
    /// Which choice of reference picture is the latest, and the read still fetching one. See
    /// `GenerationStore+Reference.swift`.
    var referenceChoice = 0
    var referenceRead: Task<Void, Never>?
    /// True while the engine is between queued generations, swapping to the model the next one
    /// needs. The queue accepts more work throughout.
    public internal(set) var isSwitchingForQueue = false
    /// True from the moment a model swap is asked for until the new model has loaded or the
    /// swap was stopped. While it is true the state passes through `.idle` without meaning
    /// "nothing to do", so nothing else may start a load.
    public internal(set) var isSwappingModel = false
    /// Called with the file an image was just written to, once it is on disk, so the app can
    /// hand the library index that one file rather than rescanning the folder for it.
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
    /// What this Mac's GPU may keep resident, which is what a fallback model is chosen by. The
    /// engine cannot ask the GPU itself; the app sets it from the runtime before `bootstrap()`,
    /// and until then the answer is the fraction of RAM a GPU-less budget assumes.
    public var memoryBudget = MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    /// Where the weights of the next model loaded should live, from the user's preference and
    /// the budget. Set through `setWeightResidencyPolicy(_:)` once the store is running, which
    /// reloads a model already up the other way; set directly before `bootstrap()`.
    public var weightResidencyPolicy = WeightResidencyPolicy(
        mode: .automatic,
        budget: MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory))
    /// Whether the decode is tiled, chosen for each run's own model when the run starts. See
    /// `GenerationStore+Tiling.swift`.
    public var vaeTilingPolicy = VAETilingPolicy(
        mode: .automatic,
        budget: MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory))
    /// How the loaded model's weights are held, for the Performance tab and the loading text.
    /// Nil while nothing is loaded.
    public internal(set) var loadedResidency: WeightResidency?
    /// Progress while model files and their destination are being changed.
    public internal(set) var modelDirectoryProgress: String?
    public let downloads: ModelDownloads
    public internal(set) var isStoppingPreparation = false
    public internal(set) var isShuttingDown = false
    var loadIdentity: UUID?
    var preparingModel: ModelDescriptor?
    var acquiredModel: AcquiredModel?
    var deletionInProgress = false
    @ObservationIgnored var storageSettlement: StorageSettlement?
    @ObservationIgnored var stopTask: Task<Void, Never>?
    public internal(set) var imageDirectoryProgress: String?

    /// How many images stay in memory before the oldest is dropped.
    static let historyLimit = 24

    // Machinery, not surface: internal rather than private so the extensions can reach them.
    /// Which backend runs which model family, or nil for a preview store, which has none and so
    /// never loads, generates, or reaches a model at all.
    let registry: BackendRegistry?
    /// How to build the one upscaler, or nil for a build that carries none — a preview store,
    /// or a tool. Nil is what greys every Upscale button, with no other rule needed.
    let upscalerFactory: UpscalerFactory?
    var library: ImageLibrary
    let logger = Logger(subsystem: "io.zephra", category: "engine")
    /// The folder models are downloaded and built in, forwarded to the inference actor as it
    /// is made and whenever it changes.
    var locations: ModelLocations
    /// The GPU runtime the actor sets the tile on before each run; nil in tests and tools.
    let runtime: (any InferenceRuntime)?

    @ObservationIgnored var inference: InferenceActor?
    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var switchTask: Task<Void, Never>?
    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var libraryTask: Task<Void, Never>?
    @ObservationIgnored var openTask: Task<Void, Never>?
    @ObservationIgnored var upscaleTask: Task<Void, Never>?

    /// Images deleted from the filmstrip before their save landed; `attach` moves the file on
    /// to Recently Deleted when it does.
    @ObservationIgnored var deletedBeforeSave: Set<GeneratedImage.ID> = []

    /// The one designated initializer. A nil `registry` makes a preview store: see
    /// `GenerationStore+Preview.swift`.
    init(
        descriptor: ModelDescriptor, registry: BackendRegistry?, output: URL?,
        locations: ModelLocations = .default, upscaler: UpscalerFactory? = nil,
        downloads: ModelDownloads = ModelDownloads(), runtime: (any InferenceRuntime)? = nil
    ) {
        self.downloads = downloads
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.registry = registry
        self.locations = locations
        self.upscalerFactory = upscaler
        self.runtime = runtime
        self.library = output.map { ImageLibrary(root: $0) } ?? .pictures()
    }
}
