import Flux2
import Foundation
import ZephraCore

/// Runs FLUX.2 klein models through Zephra's own MLX pipeline.
///
/// The instance is deliberately not Sendable: it owns a `Flux2Pipeline`, which holds MLX arrays
/// that must stay on one thread. The engine layer confines it to a serial executor.
///
/// The class is explicitly `nonisolated` so that it compiles the same way whichever target
/// links it. The app builds with default MainActor isolation, and under that setting an
/// inferred-isolated backend could not hand its non-Sendable pipeline to the pipeline's own
/// methods.
public nonisolated final class Flux2Backend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.flux2

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    let pipeline = Flux2Pipeline()
    private var loadedDescriptor: ModelDescriptor?

    /// Creates an idle backend. No weights are touched until `ensureAvailable` is called.
    public init() {}

    /// Reads the packed weights at `localPath` into memory.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        do {
            // The stream's dtype is this package's call, not the kit's: bfloat16, or float32 on
            // an M5-class GPU or under ZEPHRA_DIT_DTYPE. See `Flux2ActivationPrecision`.
            try pipeline.loadModel(
                at: localPath, activation: Flux2ActivationPrecision.resolve()
            ) { progress in
                onProgress(Flux2ProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
        loadedModelID = descriptor.id
        loadedDescriptor = descriptor
    }

    /// Produces PNG bytes for `settings`, checking for cancellation between denoising steps.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
        guard let descriptor = loadedDescriptor else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        // One throttle per run, so a frame is made at most every three quarters of a second
        // however fast the steps go by, and none at all when the environment has switched them
        // off. Nil rather than an always-refusing throttle: the loop then skips the check.
        var throttle = PreviewThrottle.environmentInterval.map(PreviewThrottle.init(interval:))
        let onPreview: Flux2Pipeline.PreviewHandler? =
            throttle == nil
            ? nil
            : { step, total, frame in
                guard throttle?.shouldMakeFrame() == true else { return }
                let started = ContinuousClock.now
                let made = frame()
                onProgress(
                    .frame(
                        after: step, of: total,
                        preview: GenerationPreview(
                            width: made.width, height: made.height, pixels: made.pixels,
                            duration: ContinuousClock.now - started)))
            }
        do {
            return try pipeline.generate(
                Flux2RequestMapper.request(for: settings, descriptor: descriptor),
                onProgress: { progress in
                    onProgress(Flux2ProgressMapper.event(from: progress))
                },
                onPreview: onPreview
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
    }

    /// Releases the weights and the scratch memory MLX was holding for them.
    public func unload() {
        pipeline.unloadModel()
        loadedModelID = nil
        loadedDescriptor = nil
    }
}
