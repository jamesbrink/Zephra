import Foundation
import ZephraCore
import ZephraMLX
import ZephraSnapshot
import ZImage

/// Runs Z-Image family models through the vendored MLX pipeline.
///
/// The instance is deliberately not Sendable: it owns a `ZImagePipeline`, which holds MLX
/// arrays that must stay on one thread. The engine layer confines it to a serial executor.
///
/// The class is explicitly `nonisolated` so that it compiles the same way whichever target
/// links it. The app builds with default MainActor isolation, and under that setting an
/// inferred-isolated backend could not hand its non-Sendable pipeline to the pipeline's own
/// nonisolated async methods.
public nonisolated final class ZImageBackend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.zImage

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    /// How the loaded weights are held: what `load` was given, since this family honours it.
    public private(set) var loadedResidency: WeightResidency?

    private var pipeline: ZImagePipeline?
    private var loadedDescriptor: ModelDescriptor?
    private var loadedSnapshot: URL?
    /// The switches the composition root read once: here, how often a preview frame is made,
    /// and, in a Debug build, `ZEPHRA_FAULT_GPU_AT_STEP`. Not `private`: `ZImageBackend+FaultProbe.swift`
    /// reads it too.
    let environment: InferenceEnvironment
    /// The VAE tile the engine set for the run about to start; see `ZImageBackendFactory`.
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

    /// Reads the weights at `localPath` into memory, the way `residency` asks for.
    ///
    /// Whatever was loaded before is released first. Two Z-Image models are 13 GB each, so
    /// holding the old one while the new one arrives would put the machine into swap; the same
    /// backend serves every variant, and it serves one at a time.
    ///
    /// Streamed, the transformer's three block stacks and the text encoder's layers are read
    /// from the shards on every pass instead of held, which is what lets a Mac that cannot hold
    /// this model run it. It says nothing about the decode: the autoencoder is resident either
    /// way and its transient is the peak, so the engine still tiles the decode when its verdict
    /// says to (`MemoryFit.requiresTiling` is true for `fitsStreamed`), through the `tile` this
    /// backend reads at the top of every run.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        let pipeline = pipeline ?? ZImagePipeline()
        self.pipeline = pipeline
        // How far the stream reads ahead is the composition root's switch, read once at launch;
        // the kit reads no environment variable of its own.
        let streaming = residency == .streamed
            ? ZImageStreaming(depth: environment.streamDepth) : nil
        do {
            try await pipeline.loadModel(modelSpec: localPath.path, streaming: streaming) {
                progress in
                onProgress(ZImageProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
        loadedModelID = descriptor.id
        loadedDescriptor = descriptor
        loadedSnapshot = localPath
        loadedResidency = residency
    }

    /// Runs one generation and returns the encoded PNG bytes.
    ///
    /// Cancellation is checked by the pipeline between denoising steps, so a cancelled task
    /// surfaces as `CancellationError`, which is passed through untouched rather than being
    /// reported as a failure.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> GeneratedMedia {
        guard let pipeline, let descriptor = loadedDescriptor, let snapshot = loadedSnapshot
        else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        let request: ZImageGenerationRequest
        do {
            request = try ZImageRequestMapper.request(
                for: settings,
                descriptor: descriptor,
                snapshot: snapshot
            )
        } catch {
            // A reference image that will not open, in practice. Reported as a generation
            // failure rather than a load one: the model is loaded and fine, the request is not.
            throw BackendError.generationFailed(error.readableMessage)
        }
        // The vendored kit keeps its tile as a knob of its own; it is set from the engine's
        // choice for this run, on this queue, just before the run that reads it.
        VAETiledDecode.latentTile = tile.value
        // One throttle per run, and no hook at all when frames are switched off, so the loop
        // skips the check; see `PreviewFrameReporter`.
        let previewHandler: ZImagePipeline.PreviewHandler? = PreviewFrameReporter.handler(
            interval: environment.previewInterval, onProgress: onProgress)
        do {
            let png = try await pipeline.generateToMemory(
                request,
                progressHandler: { progress in
                    #if DEBUG
                    self.fireFaultProbeIfNeeded(for: progress)
                    #endif
                    onProgress(ZImageProgressMapper.event(from: progress))
                },
                previewHandler: previewHandler
            )
            return .image(png: png)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
    }

    /// Drops the weights and clears the GPU cache, leaving the backend reusable.
    public func unload() {
        pipeline?.unloadModel()
        loadedModelID = nil
        loadedDescriptor = nil
        loadedSnapshot = nil
        loadedResidency = nil
    }
}
