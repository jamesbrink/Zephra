import Flux2
import Foundation
import ZephraCore
import ZephraMLX

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

    /// How the loaded weights are held: what the last load did.
    public private(set) var loadedResidency: WeightResidency?

    let pipeline = Flux2Pipeline()
    private var loadedDescriptor: ModelDescriptor?
    /// The switches the composition root read once: the stream's dtype override and how often
    /// a preview frame is made.
    private let environment: InferenceEnvironment
    /// The VAE tile the engine set for the run about to start; see `Flux2BackendFactory`.
    private let tile: VAETileSetting

    /// Creates an idle backend running under `environment`, decoding at whatever `tile` holds
    /// when a run starts. No weights are touched until `ensureAvailable` is called.
    public init(environment: InferenceEnvironment, tile: VAETileSetting) {
        self.environment = environment
        self.tile = tile
    }

    /// An idle backend under the default switches, for tests that only ask about the disk.
    public convenience init() {
        self.init(environment: InferenceEnvironment(), tile: VAETileSetting())
    }

    /// Reads the packed weights at `localPath` into memory, held the way `residency` says:
    /// streamed, the encoder's 27 layers and the transformer's 25 blocks are read from disk on
    /// every pass rather than held.
    ///
    /// The decode is tiled or not by the engine either way — a streamed fit still has the
    /// autoencoder's peak to pay, which is what `requiresTiling` covers.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        let streaming = residency == .streamed ? Flux2Streaming(depth: environment.streamDepth) : nil
        do {
            // The stream's dtype is this package's call, not the kit's: bfloat16, or float32 on
            // an M5-class GPU or under ZEPHRA_DIT_DTYPE. See `Flux2ActivationPrecision`.
            try pipeline.loadModel(
                at: localPath,
                activation: Flux2ActivationPrecision.resolve(environment: environment),
                streaming: streaming
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
        loadedResidency = residency
    }

    /// Produces PNG bytes for `settings`, checking for cancellation between denoising steps.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> GeneratedMedia {
        guard let descriptor = loadedDescriptor else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        // One throttle per run, and no hook at all when frames are switched off, so the loop
        // skips the check; see `PreviewFrameReporter`.
        let onPreview: Flux2Pipeline.PreviewHandler? = PreviewFrameReporter.handler(
            interval: environment.previewInterval, onProgress: onProgress)
        do {
            var request = Flux2RequestMapper.request(for: settings, descriptor: descriptor)
            request.vaeTile = tile.value
            let png = try pipeline.generate(
                request,
                onProgress: { progress in
                    onProgress(Flux2ProgressMapper.event(from: progress))
                },
                onPreview: onPreview
            )
            return .image(png: png)
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
        loadedResidency = nil
    }
}
