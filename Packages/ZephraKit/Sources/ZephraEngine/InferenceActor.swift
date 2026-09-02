import Foundation
import ZephraCore

/// The only place backend code runs.
///
/// A generation is tens of seconds of synchronous Metal work. Running that on the cooperative
/// thread pool would starve every other task in the process, so this actor takes a serial
/// dispatch queue as its executor and keeps the whole backend on it. The backend itself is not
/// Sendable, which is why it arrives as a factory and is built here rather than passed in.
actor InferenceActor {
    /// The prompt used for the throwaway generation that pays the first-run compilation cost.
    private static let warmUpPrompt = "a plain grey square"
    /// Deliberately small: warming up is about compiling kernels, not about image quality.
    private static let warmUpSize = ImageSize(width: 512, height: 512)

    private let queue = DispatchSerialQueue(label: "io.zephra.inference", qos: .userInitiated)
    private let factory: BackendFactory
    private var backend: (any ImageGenerationBackend)?

    /// Pins every method of this actor to the inference queue instead of the cooperative pool.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Creates an actor that will build its backend from `factory` the first time it needs one.
    init(factory: @escaping BackendFactory) {
        self.factory = factory
    }

    /// Fetches the weights if they are missing, then reads them into memory, reporting both
    /// stages through `events`. Doing nothing is the right answer if the model is already loaded.
    func prepare(_ descriptor: ModelDescriptor, events: EngineEventSink) async throws {
        let live = backend(for: descriptor)
        guard live.loadedModelID != descriptor.id else { return }
        let localPath = try await live.ensureAvailable(descriptor) { event in
            events.send(.download(event))
        }
        try await live.load(descriptor, at: localPath) { event in
            events.send(.progress(event))
        }
    }

    /// Runs one tiny generation and throws the result away, so the first image the user asks
    /// for is not the one that pays for kernel compilation.
    func warmUp(_ descriptor: ModelDescriptor) async throws {
        let live = backend(for: descriptor)
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

    /// Releases the weights. The next `prepare` will load them again.
    func unload() {
        backend?.unload()
        backend = nil
    }

    private func backend(for descriptor: ModelDescriptor) -> any ImageGenerationBackend {
        if let backend { return backend }
        let made = factory(descriptor)
        backend = made
        return made
    }
}
