import Foundation
import QwenImage21
import ZephraCore
import ZephraMLX

/// Runs Qwen-Image 2.1 models through Zephra's own MLX pipeline.
///
/// The instance is deliberately not Sendable: it owns a `QwenImage21Pipeline`, which holds MLX
/// arrays that must stay on one thread. The engine layer confines it to a serial executor.
///
/// The class is explicitly `nonisolated` so that it compiles the same way whichever target
/// links it. The app builds with default MainActor isolation, and under that setting an
/// inferred-isolated backend could not hand its non-Sendable pipeline to the pipeline's own
/// methods.
public nonisolated final class QwenImage21Backend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.qwenImage21

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    /// How the loaded weights are held: what the last load did.
    public private(set) var loadedResidency: WeightResidency?

    let pipeline = QwenImage21Pipeline()
    private var loadedDescriptor: ModelDescriptor?
    /// The switches the composition root read once: the stream's dtype override and how often
    /// a preview frame is made.
    private let environment: InferenceEnvironment
    /// The VAE tile the engine set for the run about to start; see `QwenImage21BackendFactory`.
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
    /// streamed, the transformer's 32 blocks and the decoder's 36 layers are read from disk on
    /// every pass rather than held. The vision tower and the autoencoder never stream.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        let streaming =
            residency == .streamed ? QwenImage21Streaming(depth: environment.streamDepth) : nil
        do {
            // The stream's dtype is this package's call, not the kit's: bfloat16, or float32 on
            // an M5-class GPU or under ZEPHRA_DIT_DTYPE. See `QwenImage21ActivationPrecision`.
            try pipeline.loadModel(
                at: localPath,
                activation: QwenImage21ActivationPrecision.resolve(environment: environment),
                streaming: streaming
            ) { progress in
                onProgress(QwenImage21ProgressMapper.event(from: progress))
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
        let onPreview: QwenImage21Pipeline.PreviewHandler? = PreviewFrameReporter.handler(
            interval: environment.previewInterval, onProgress: onProgress)
        do {
            var request = QwenImage21RequestMapper.request(for: settings, descriptor: descriptor)
            request.vaeTile = QwenImage21RequestMapper.vaeTile(from: tile.value)
            let result = try pipeline.generate(
                request,
                onProgress: { progress in
                    onProgress(QwenImage21ProgressMapper.event(from: progress))
                },
                onPreview: onPreview
            )
            return .image(png: result.png)
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
