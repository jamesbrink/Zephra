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
    /// What the next generation will use. Edited directly by the UI — and an edit means the
    /// capsule is the user's again, not a picture's, so the running card leaves it alone.
    public var settings: GenerationSettings { didSet { capsuleHoldsPicture = false } }
    /// The model the next generation will use. Change it with `switchModel(to:)`; queued
    /// generations keep the model they were queued for.
    public internal(set) var descriptor: ModelDescriptor
    /// What is on disk for each known model, by descriptor id. Filled in at bootstrap and after
    /// every load; a model missing from the map has not been looked at yet.
    public internal(set) var pendingOutputBatches: [UUID: UUID] = [:]
    public internal(set) var savedBatchCounts: [UUID: Int] = [:]
    var savedBatchOrder: [UUID] = []

    public internal(set) var availability: [ModelDescriptor.ID: ModelAvailability] = [:]
    /// Wall-clock time of the last completed generation.
    public internal(set) var lastDuration: Duration?
    public let timings = WorkloadTimings()
    var timingRevisions: [String: String] = [:]
    var timingDirectories: [String: URL] = [:]
    var timingRunStarted: ContinuousClock.Instant?
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
    /// True when `descriptor` was taken from a picture rather than chosen, and the loaded model
    /// stays put until Generate asks for the chosen one; see `GenerationStore+Interaction`.
    public internal(set) var modelAwaitsGenerate = false
    /// True while the capsule holds a picture's settings (`select(_:)`) rather than the user's
    /// own, which is when the running card puts the run's back; see `watchRun()`.
    var capsuleHoldsPicture = false
    /// The directory those weights were read from, so a settings row can tell the one copy
    /// that is in use from a duplicate of the same model elsewhere. Nil while none are.
    public internal(set) var loadedDirectory: URL?
    /// Which choice of reference picture is the latest, and the read still fetching one. See
    /// `GenerationStore+Reference.swift`. The number is readable so a view drawing the
    /// picture can key its work on the choice rather than compare the bytes.
    public internal(set) var referenceChoice = 0
    /// Moves on every change to the well's list, a reorder included, which moves neither the
    /// ticket nor the count; a tile keys its thumbnail on it. See `settleAfterReferenceChange`.
    public internal(set) var referenceRevision = 0
    var referenceRead: Task<Void, Never>?
    /// Why the last picture offered to the well was not taken, for the interface to show, and
    /// nil whenever the last change was taken. Set and cleared in
    /// `GenerationStore+ReferenceStrip`, which is the only thing that refuses a picture.
    public internal(set) var referenceNote: String?
    /// True while the engine is between queued generations, swapping to the model the next one
    /// needs. The queue accepts more work throughout.
    public internal(set) var isSwitchingForQueue = false
    /// True once the GPU has stopped running this process's work: the driver has put this
    /// client on its ignore list and every submission after that is answered without being
    /// run. Sticky for the rest of the launch, and the whole of `GenerationStore+DeviceLoss`.
    public internal(set) var deviceLost = false
    /// True from the moment a model swap is asked for until the new model has loaded or the
    /// swap was stopped; the state passes through `.idle` meanwhile, so nothing else may load.
    public internal(set) var isSwappingModel = false
    /// Called with the file an image was just written to, so the app can hand the library index
    /// that one file rather than rescanning the folder for it.
    public var onImageSaved: (@MainActor (URL) -> Void)?
    /// Called with the file an image deleted from the filmstrip was moved out of, so the app
    /// can tell the library index without waiting for a folder watch.
    public var onImageDeleted: (@MainActor (URL) -> Void)?
    /// The most recent thing the library could not do for this store, or nil when it worked.
    public internal(set) var lastLibraryFailure: LibraryFailure?
    /// Whether a load ends with a throwaway generation that pays the kernel-compilation cost
    /// up front; the app sets it from the user's preference before it calls `bootstrap()`.
    public var warmsUpAfterLoad = true
    /// How often a run shows a frame of the picture it is making; the app sets it from the
    /// Live preview preference. Read as each run starts, so a change applies to the next run.
    /// A warm-up shows none whatever this says.
    public var previewCadence: PreviewCadence = .balanced
    /// When weights are read in: at launch and on every pick, or only when asked for.
    public var loadingMode: ModelLoadingMode = .automatic
    /// How long the weights may sit idle before they are given back; the app sets it.
    public var idleUnloadDelay: IdleUnloadDelay = .never { didSet { armIdleUnload() } }
    /// The idle clock, cancelled and re-armed by every transition.
    @ObservationIgnored var idleTask: Task<Void, Never>?
    /// How the idle clock waits; the one seam a suite about it replaces.
    @ObservationIgnored var idleWait: @Sendable (Duration) async -> Void = {
        try? await Task.sleep(for: $0)
    }
    /// The residency the next load must use whatever the policy says; consumed once.
    @ObservationIgnored var residencyOverride: WeightResidency?
    /// What this Mac's GPU may keep resident, which is what a fallback model is chosen by; the
    /// app sets it from the runtime before `bootstrap()`, else a GPU-less budget's share of RAM.
    public var memoryBudget = MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    /// Where the weights of the next model loaded should live. Set through
    /// `setWeightResidencyPolicy(_:)` once running, which reloads a model up the other way.
    public var weightResidencyPolicy = WeightResidencyPolicy(
        mode: .automatic,
        budget: MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory))
    /// Whether the decode is tiled, chosen for each run's own model when the run starts. See
    /// `GenerationStore+Tiling.swift`.
    public var vaeTilingPolicy = VAETilingPolicy(
        mode: .automatic,
        budget: MemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory))
    /// How the loaded model's weights are held, for the Performance tab; nil while none are.
    public internal(set) var loadedResidency: WeightResidency?
    /// Progress while model files and their destination are being changed.
    public internal(set) var modelDirectoryProgress: String?
    public let promptHistory: PromptHistory
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
    /// Which backend runs which model family; nil for a preview store, which never loads.
    let registry: BackendRegistry?
    /// How to build the one upscaler, or nil for a build that carries none — a preview store,
    /// or a tool. Nil is what greys every Upscale button, with no other rule needed.
    let upscalerFactory: UpscalerFactory?
    /// How a clip's last frames are read back and how clips are joined, or nil for a build
    /// that cannot — a preview store, or a tool. Nil is what greys Extend Clip, with no other
    /// rule needed; see `GenerationStore+Extend.swift`.
    public let clips: (any ClipEditing)?
    var library: ImageLibrary
    let logger = Logger(subsystem: "io.zephra", category: "engine")
    /// The folder models are downloaded and built in, forwarded to the inference actor as it
    /// is made and whenever it changes.
    var locations: ModelLocations
    /// The GPU runtime the actor sets the tile on before each run; nil in tests and tools.
    let runtime: (any InferenceRuntime)?
    /// How the Mac's own free memory is read, for the check before every load and every run;
    /// nil for a build with nothing to ask, which then judges by the budget alone. Injected
    /// like `runtime` so a refusal never depends on what else is running while a suite runs.
    let machineMemory: (any MachineMemoryReader)?

    @ObservationIgnored var inference: InferenceActor?
    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var switchTask: Task<Void, Never>?
    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var libraryTask: Task<Void, Never>?
    @ObservationIgnored var openTask: Task<Void, Never>?
    /// A test's hold on a library read, run before the file is read; nil outside tests.
    @ObservationIgnored var beforeLibraryRead: (@Sendable () -> Void)?
    @ObservationIgnored var upscaleTask: Task<Void, Never>?

    /// Images deleted from the filmstrip before their save landed; `attach` moves the file on
    /// to Recently Deleted when it does.
    @ObservationIgnored var deletedBeforeSave: Set<GeneratedImage.ID> = []
    /// The chained clips in progress, by chain: the segments made so far and what the clip
    /// was asked to be. See `GenerationStore+Chaining.swift`.
    @ObservationIgnored var chains: [UUID: ChainProgress] = [:]

    /// The one designated initializer. A nil `registry` makes a preview store: see
    /// `GenerationStore+Preview.swift`.
    init(
        descriptor: ModelDescriptor, registry: BackendRegistry?, output: URL?,
        locations: ModelLocations = .default, upscaler: UpscalerFactory? = nil,
        downloads: ModelDownloads = ModelDownloads(), runtime: (any InferenceRuntime)? = nil,
        clips: (any ClipEditing)? = nil, machineMemory: (any MachineMemoryReader)? = nil
    ) {
        self.promptHistory = PromptHistory(file: registry == nil ? nil :
            (output ?? ImageLibrary.pictures().root).appendingPathComponent(".zephra-prompt-history.json"))
        self.machineMemory = machineMemory
        self.downloads = downloads
        self.clips = clips
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.registry = registry
        self.locations = locations
        self.upscalerFactory = upscaler
        self.runtime = runtime
        self.library = output.map { ImageLibrary(root: $0) } ?? .pictures()
        // A download nobody is waiting on has no load behind it to re-read the disk, so the
        // pool says when one lands and this is what answers.
        downloads.onUnborrowedCompletion = { [weak self] _ in
            guard let self, self.acceptsWork else { return }
            Task { await self.refreshAvailability() }
        }
    }
}
