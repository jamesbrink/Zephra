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
    /// This session's images, newest first, capped at 24.
    public internal(set) var history: [GeneratedImage] = []
    /// What the next generation will use. Edited directly by the UI.
    public var settings: GenerationSettings
    /// The model this store drives.
    public internal(set) var descriptor: ModelDescriptor
    /// Wall-clock time of the last completed generation.
    public internal(set) var lastDuration: Duration?
    /// The most recent image that could not be written, or nil when the last one saved. Shown
    /// as a notice; it never stops the engine or the queue.
    public internal(set) var lastSaveFailure: SaveFailure?
    /// Generations waiting their turn, oldest first. Runs down by itself after each image.
    public internal(set) var queue: [QueuedGeneration] = []
    /// Whether a load ends with a throwaway generation that pays the kernel-compilation cost
    /// up front. The engine has no idea where the answer comes from; the app sets it from the
    /// user's preference before it calls `bootstrap()`.
    public var warmsUpAfterLoad = true

    /// How many images stay in memory before the oldest is dropped.
    static let historyLimit = 24

    // Machinery, not surface. These are internal rather than private only so the generation
    // half of this type, in GenerationStore+Generation.swift, can reach them.
    /// How the store builds its backend, or nil for a preview store, which has none and so
    /// never loads, generates, or reaches a model at all.
    let backendFactory: BackendFactory?
    let library: ImageLibrary
    let logger = Logger(subsystem: "io.zephra", category: "engine")

    @ObservationIgnored var inference: InferenceActor?
    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?

    /// Creates a store for one model. `outputDirectory` nil means ~/Pictures/Zephra.
    public convenience init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        backendFactory: @escaping BackendFactory,
        outputDirectory: URL? = nil
    ) {
        self.init(descriptor: descriptor, factory: backendFactory, outputDirectory: outputDirectory)
    }

    /// The one designated initializer. A nil `factory` makes a preview store: see
    /// `GenerationStore+Preview.swift`.
    init(descriptor: ModelDescriptor, factory: BackendFactory?, outputDirectory: URL?) {
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.backendFactory = factory
        self.library = outputDirectory.map { ImageLibrary(root: $0) } ?? .pictures()
    }

    /// True when a generation can start right now: the engine is ready and there is a prompt.
    public var canGenerate: Bool { state.acceptsGeneration && settings.isReadyToGenerate }

    /// True when `generate()` will do something: start now, or queue behind the running one.
    public var canQueue: Bool { settings.isReadyToGenerate && (state.acceptsGeneration || isRunning) }

    /// Whether a generation is in flight, including one that is being stopped.
    var isRunning: Bool {
        switch state {
        case .generating, .cancelling: true
        default: false
        }
    }

    /// Starts a generation with the current settings, or queues it if one is already running.
    /// Does nothing unless `canQueue`.
    public func generate() {
        guard canQueue else { return }
        let request = descriptor.capabilities.clamp(settings)
        if isRunning {
            queue.append(QueuedGeneration(settings: request))
            logger.info("queued generation, \(self.queue.count) waiting")
        } else {
            start(request)
        }
    }

    /// Stops whatever the engine is busy with.
    ///
    /// During a generation that means finishing the current step and dropping the queue: the
    /// backend only looks for a cancel between denoising steps, so `.cancelling` can sit there
    /// for one step's worth. During a download, a load, or a warm-up it means abandoning that
    /// and returning to `.idle`, from where the canvas offers to start again.
    public func cancel() {
        switch state {
        case .generating:
            queue.removeAll()
            transition(to: .cancelling)
            generationTask?.cancel()
        case .checkingModel, .downloading, .loading, .warmingUp:
            bootstrapTask?.cancel()
        case .idle, .ready, .cancelling, .failed:
            break
        }
    }

    /// Takes one waiting generation out of the queue.
    public func removeFromQueue(_ id: QueuedGeneration.ID) {
        queue.removeAll { $0.id == id }
    }

    /// Empties the queue without touching the running generation.
    public func clearQueue() { queue.removeAll() }

    /// Shows an earlier image on the canvas and adopts its settings, so the obvious next move
    /// is to tweak one thing and generate a variation.
    public func select(_ image: GeneratedImage) {
        current = image
        settings = image.settings
    }

    /// Picks a fresh seed for the next generation.
    public func randomizeSeed() { settings = settings.withRandomSeed() }

    /// Waits for everything this store has in flight. A seam for tests, which need generation
    /// and the file write that follows it to be finished before they assert.
    func settle() async {
        await bootstrapTask?.value
        await generationTask?.value
        await saveTask?.value
    }
}
