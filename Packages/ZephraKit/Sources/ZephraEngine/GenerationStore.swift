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

    /// How many images stay in memory before the oldest is dropped.
    static let historyLimit = 24

    // Machinery, not surface. These are internal rather than private only so the generation
    // half of this type, in GenerationStore+Generation.swift, can reach them.
    let backendFactory: BackendFactory
    let library: ImageLibrary
    let logger = Logger(subsystem: "io.zephra", category: "engine")

    @ObservationIgnored var inference: InferenceActor?
    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var generationTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?

    /// Creates a store for one model. `outputDirectory` nil means ~/Pictures/Zephra.
    public init(
        descriptor: ModelDescriptor = ModelCatalog.default,
        backendFactory: @escaping BackendFactory,
        outputDirectory: URL? = nil
    ) {
        self.descriptor = descriptor
        self.settings = GenerationSettings.defaults(for: descriptor)
        self.backendFactory = backendFactory
        self.library = outputDirectory.map { ImageLibrary(root: $0) } ?? .pictures()
    }

    /// True when a generation can start: the engine is ready and there is a prompt.
    public var canGenerate: Bool { state.acceptsGeneration && settings.isReadyToGenerate }

    /// Finds or downloads the model, loads it, and warms up. Call once from the root view.
    /// Calling it again once the engine is running is a no-op, so a re-rendered root is free.
    public func bootstrap() async {
        switch state {
        case .idle, .failed: break
        default: return
        }
        transition(to: .checkingModel)
        let inference = inference ?? InferenceActor(factory: backendFactory)
        self.inference = inference
        let pump = EngineEventPump { [weak self] event in self?.applyLoadEvent(event) }
        do {
            try await pump.run { sink in try await inference.prepare(descriptor, events: sink) }
            transition(to: .warmingUp)
            try await inference.warmUp(descriptor)
            transition(to: .ready)
        } catch is CancellationError {
            transition(to: .idle)
        } catch let error as BackendError {
            transition(to: .failed(.backend(error)))
        } catch {
            transition(to: .failed(.backend(.loadFailed(error.localizedDescription))))
        }
    }

    /// Starts a generation with the current settings. Safe to call only when `canGenerate`.
    public func generate() {
        guard canGenerate, let inference else { return }
        let request = descriptor.capabilities.clamp(settings)
        transition(to: .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)))
        generationTask = Task { await self.run(request, on: inference) }
    }

    /// Stops the in-flight generation after its current step. The backend only looks for a
    /// cancel between denoising steps, so `.cancelling` can sit there for one step's worth.
    public func cancel() {
        guard case .generating = state else { return }
        transition(to: .cancelling)
        generationTask?.cancel()
    }

    /// Leaves `.failed` and runs `bootstrap` again.
    public func retry() {
        guard case .failed = state else { return }
        transition(to: .idle)
        bootstrapTask = Task { await self.bootstrap() }
    }

    /// Shows an earlier image on the canvas and adopts its settings, so the obvious next move
    /// is to tweak one thing and generate a variation.
    public func select(_ image: GeneratedImage) {
        current = image
        settings = image.settings
    }

    /// Picks a fresh seed for the next generation.
    public func randomizeSeed() { settings = settings.withRandomSeed() }

    /// A store frozen in one state, for SwiftUI previews. Never touches a backend.
    public static func preview(state: EngineState, image: GeneratedImage? = nil) -> GenerationStore {
        let store = GenerationStore(backendFactory: { _ in fatalError("preview store has no backend") })
        store.state = state
        store.current = image
        store.history = image.map { [$0] } ?? []
        store.settings.prompt = "A lighthouse at dusk, fog rolling in over black rocks"
        return store
    }

    /// Waits for everything this store has in flight. A seam for tests, which need generation
    /// and the file write that follows it to be finished before they assert.
    func settle() async {
        await bootstrapTask?.value
        await generationTask?.value
        await saveTask?.value
    }
}
