import Foundation
import ZephraCore

/// The only place backend code runs.
///
/// A generation is tens of seconds of synchronous Metal work. Running that on the cooperative
/// thread pool would starve every other task in the process, so this actor takes a serial
/// dispatch queue as its executor and keeps the whole backend on it. Backends are not Sendable,
/// which is why a registry of factories arrives here and the backend itself is built inside.
actor InferenceActor {
    /// The prompt used for the throwaway generation that pays the first-run compilation cost.
    private static let warmUpPrompt = "a plain grey square"
    /// Deliberately small: warming up is about compiling kernels, not about image quality.
    private static let warmUpSize = ImageSize(width: 512, height: 512)

    private let queue = DispatchSerialQueue(label: "io.zephra.inference", qos: .userInitiated)
    private let registry: BackendRegistry
    private var backend: (any ImageGenerationBackend)?
    private var backendID: BackendID?
    /// The directory the resident weights were read from, for `prepare` to hand back again
    /// when asked for a model that is already up.
    private var loadedPath: URL?
    private let upscalerFactory: UpscalerFactory?
    private var upscaler: (any ImageUpscaler)?
    /// The folder models are kept in, as the last `setLocations` left it. Read at the top of
    /// each operation rather than held by the backend, so a folder chosen while a download is
    /// running applies to the next one and never to the one in flight.
    private var locations: ModelLocations

    /// Pins every method of this actor to the inference queue instead of the cooperative pool.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Creates an actor that will build backends out of `registry` as descriptors arrive, and
    /// the one upscaler `upscaler` makes the first time a picture is made larger. A nil factory
    /// is a build with no upscaler in it, which every upscale then fails as weights missing.
    init(
        registry: BackendRegistry,
        locations: ModelLocations = .default,
        upscaler: UpscalerFactory? = nil
    ) {
        self.registry = registry
        self.locations = locations
        self.upscalerFactory = upscaler
    }

    /// Keeps models in `locations` from the next `prepare` onwards. A transfer already running
    /// finishes where it started: moving a download half-way through would leave two partial
    /// copies and finish neither.
    func setLocations(_ locations: ModelLocations) {
        self.locations = locations
    }

    /// Fetches the weights if they are missing, packs them if the family loads something other
    /// than its download, then reads them into memory, reporting every stage through `events`,
    /// and returns the directory the weights were read from. Doing nothing, and handing back
    /// the same directory, is the right answer if the model is already loaded.
    @discardableResult
    func prepare(_ descriptor: ModelDescriptor, events: EngineEventSink) async throws -> URL {
        let live = try backend(for: descriptor)
        if live.loadedModelID == descriptor.id, let loadedPath { return loadedPath }
        // Read once: a folder changed during the download must not have the build looking
        // for what was fetched, or writing, under a root the download never used.
        let locations = self.locations
        let downloaded = try await live.ensureAvailable(descriptor, locations: locations) { event in
            events.send(.download(event))
        }
        let localPath = try await live.build(descriptor, at: downloaded, locations: locations) {
            event in
            events.send(.build(event))
        }
        try await live.load(descriptor, at: localPath) { event in
            events.send(.progress(event))
        }
        loadedPath = localPath
        return localPath
    }

    /// Whether `descriptor`'s weights are already on this Mac. Never downloads, and never
    /// disturbs what is loaded: a backend built only to answer this is thrown away afterwards.
    func availability(of descriptor: ModelDescriptor) async -> ModelAvailability {
        if let backend, backendID == descriptor.backend {
            return await backend.availability(of: descriptor, locations: locations)
        }
        guard let probe = try? registry.make(descriptor) else {
            return .missing(reason: "No engine in this build can run \(descriptor.backend.rawValue) models.")
        }
        return await probe.availability(of: descriptor, locations: locations)
    }

    /// Runs one tiny generation and throws the result away, so the first image the user asks
    /// for is not the one that pays for kernel compilation.
    func warmUp(_ descriptor: ModelDescriptor) async throws {
        let live = try backend(for: descriptor)
        let settings = descriptor.capabilities.clamp(
            GenerationSettings(
                prompt: Self.warmUpPrompt,
                size: Self.warmUpSize,
                steps: 1,
                guidance: descriptor.capabilities.defaultGuidance,
                seed: 0
            )
        )
        _ = try await live.generate(settings) { _ in }
    }

    /// Produces PNG bytes, timing the denoising loop so the interface can show a countdown even
    /// when the backend reports no pace of its own.
    func generate(_ settings: GenerationSettings, events: EngineEventSink) async throws -> Data {
        guard let backend else {
            throw BackendError.loadFailed("The model has not been loaded yet.")
        }
        var timer = StepTimer()
        return try await backend.generate(settings) { event in
            events.send(.progress(timer.annotated(event)))
        }
    }

    /// Makes `png` `request.factor` times larger on each edge, on this same serial queue, so an
    /// upscale and a generation can never both be running Metal work.
    ///
    /// The upscaler is built on first use and kept afterwards. It is five megabytes and it is
    /// not the model: dropping it would make every model switch re-read its weights.
    func upscale(_ png: Data, _ request: UpscaleRequest, events: EngineEventSink) async throws
        -> Data
    {
        guard let live = try liveUpscaler() else {
            throw UpscaleError.weightsMissing("this build carries no upscaler")
        }
        return try await live.upscale(png, request) { event in
            events.send(.upscale(event))
        }
    }

    /// Releases the weights. The next `prepare` will load them again. The first half of
    /// switching models: the store calls this before it bootstraps the next one. The upscaler
    /// is left alone: it is not the model, and it is not what the memory was needed for.
    func unload() {
        backend?.unload()
        backend = nil
        backendID = nil
    }

    /// The one upscaler, built on first use, or nil in a build that was given no factory.
    private func liveUpscaler() throws -> (any ImageUpscaler)? {
        if let upscaler { return upscaler }
        guard let upscalerFactory else { return nil }
        let made = upscalerFactory()
        upscaler = made
        return made
    }

    /// The live backend, rebuilt whenever the descriptor names a different family. Two backends
    /// are never held at once: the old one is unloaded before the new one exists.
    private func backend(for descriptor: ModelDescriptor) throws -> any ImageGenerationBackend {
        if let backend, backendID == descriptor.backend { return backend }
        unload()
        let made = try registry.make(descriptor)
        backend = made
        backendID = descriptor.backend
        return made
    }
}
