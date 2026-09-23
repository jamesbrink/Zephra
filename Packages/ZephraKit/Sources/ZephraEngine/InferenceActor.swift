import Foundation
import ZephraCore
import ZephraSnapshot

/// The only place backend code runs.
///
/// A generation is tens of seconds of synchronous Metal work. Running that on the cooperative
/// thread pool would starve every other task in the process, so this actor takes a serial
/// dispatch queue as its executor and keeps the whole backend on it. Backends are not Sendable,
/// which is why a registry of factories arrives here and the backend itself is built inside.
actor InferenceActor {
    /// The prompt used for the throwaway generation that pays the first-run compilation cost.
    static let warmUpPrompt = "a plain grey square"
    /// Deliberately small: warming up is about compiling kernels, not about image quality.
    static let warmUpSize = ImageSize(width: 512, height: 512)

    private let queue = DispatchSerialQueue(label: "io.zephra.inference", qos: .userInitiated)
    let registry: BackendRegistry
    var backend: (any ImageGenerationBackend)?
    var backendID: BackendID?
    /// The directory the resident weights were read from, for `prepare` to hand back again
    /// when asked for a model that is already up.
    var loadedPath: URL?
    /// How the loaded weights are held. Pinned beside `loadedPath` because a model already up
    /// the other way is not already up: asking for it streamed after it was loaded resident
    /// is a reload, the same as asking for a different model.
    var loadedResidency: WeightResidency?
    private let upscalerFactory: UpscalerFactory?
    private var upscaler: (any ImageUpscaler)?
    /// The GPU runtime whose VAE tile is set at the start of each run, on this queue, so the
    /// write is ordered before the decode that reads it. Nil in tests and tools.
    let runtime: (any InferenceRuntime)?
    /// The folder models are kept in, as the last `setLocations` left it. Read at the top of
    /// each operation rather than held by the backend, so a folder chosen while a download is
    /// running applies to the next one and never to the one in flight.
    var locations: ModelLocations

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
        upscaler: UpscalerFactory? = nil,
        runtime: (any InferenceRuntime)? = nil
    ) {
        self.registry = registry
        self.locations = locations
        self.upscalerFactory = upscaler
        self.runtime = runtime
    }

    /// Keeps models in `locations` from the next `prepare` onwards. A transfer already running
    /// finishes where it started: moving a download half-way through would leave two partial
    /// copies and finish neither.
    func setLocations(_ locations: ModelLocations) {
        self.locations = locations
    }

    /// Produces the finished media, timing the denoising loop so the interface can show a countdown even
    /// when the backend reports no pace of its own. `tile` is the VAE tile this run decodes
    /// at, set here, on this queue, so the run's own model is what it applies to.
    func generate(_ settings: GenerationSettings, tile: Int?, events: EngineEventSink) async throws
        -> GeneratedMedia
    {
        guard let backend else {
            throw BackendError.loadFailed("The model has not been loaded yet.")
        }
        runtime?.setVAETileSize(tile)
        var timer = StepTimer()
        let media = try await catchingDeviceErrors {
            try await backend.generate(settings) { event in
                events.send(.progress(timer.annotated(event)))
            }
        }
        // A backend looks for a cancel between steps and not after the decode; a stop that
        // landed during the decode is honoured here, so a stopped run never hands back bytes.
        try Task.checkCancellation()
        return media
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
        do {
            return try await catchingDeviceErrors {
                try await live.upscale(png, request) { event in
                    events.send(.upscale(event))
                }
            }
        } catch BackendError.deviceFailed, BackendError.deviceVictim {
            // An upscale's failures are `UpscaleError`s, which reach the person as a notice on
            // the picture; a `BackendError` here would put up the failure screen whose remedy
            // is to reload a model the upscaler never needed. The raw text is already logged.
            throw UpscaleError.failed("The GPU stopped responding. Try again.")
        }
    }

    /// Releases the weights. The next `prepare` will load them again. The first half of
    /// switching models: the store calls this before it bootstraps the next one. The upscaler
    /// is left alone: it is not the model, and it is not what the memory was needed for.
    ///
    /// The allocator's cache goes back last, after the backend has dropped its arrays: called
    /// first it would hand back what the model is still holding, which is nothing, and the
    /// gigabytes the released weights leave behind would sit in the cache while the next
    /// model's load measured the machine and found them taken.
    ///
    /// The device is drained before that: a streamed pass leaves reads of the next layers
    /// queued against the model's own files, which a caller that unloads to move that folder
    /// would pull out from under them.
    func unload() {
        backend?.unload()
        backend = nil
        backendID = nil
        loadedPath = nil
        loadedResidency = nil
        runtime?.synchronize()
        runtime?.releaseCache()
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
    func backend(for descriptor: ModelDescriptor) throws -> any ImageGenerationBackend {
        if let backend, backendID == descriptor.backend { return backend }
        unload()
        let made = try registry.make(descriptor)
        backend = made
        backendID = descriptor.backend
        return made
    }
}
