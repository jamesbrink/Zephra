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

    /// Pins every method of this actor to the inference queue instead of the cooperative pool.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Creates an actor that will build backends out of `registry` as descriptors arrive.
    init(registry: BackendRegistry) {
        self.registry = registry
    }

    /// Fetches the weights if they are missing, packs them if the family loads something other
    /// than its download, then reads them into memory, reporting every stage through `events`. Doing nothing is the right answer if the model is already loaded.
    func prepare(_ descriptor: ModelDescriptor, events: EngineEventSink) async throws {
        let live = try backend(for: descriptor)
        guard live.loadedModelID != descriptor.id else { return }
        let downloaded = try await live.ensureAvailable(descriptor) { event in
            events.send(.download(event))
        }
        let localPath = try await live.build(descriptor, at: downloaded) { event in
            events.send(.build(event))
        }
        try await live.load(descriptor, at: localPath) { event in
            events.send(.progress(event))
        }
    }

    /// Whether `descriptor`'s weights are already on this Mac. Never downloads, and never
    /// disturbs what is loaded: a backend built only to answer this is thrown away afterwards.
    func availability(of descriptor: ModelDescriptor) async -> ModelAvailability {
        if let backend, backendID == descriptor.backend {
            return await backend.availability(of: descriptor)
        }
        guard let probe = try? registry.make(descriptor) else {
            return .missing(reason: "No engine in this build can run \(descriptor.backend.rawValue) models.")
        }
        return await probe.availability(of: descriptor)
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

    /// Releases the weights. The next `prepare` will load them again. The first half of
    /// switching models: the store calls this before it bootstraps the next one.
    func unload() {
        backend?.unload()
        backend = nil
        backendID = nil
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
