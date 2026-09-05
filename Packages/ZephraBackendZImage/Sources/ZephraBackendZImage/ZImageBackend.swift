import Foundation
import ZephraCore
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

    private var pipeline: ZImagePipeline?
    private var loadedDescriptor: ModelDescriptor?
    private var loadedSnapshot: URL?

    /// Creates an idle backend. No weights are touched until `ensureAvailable` is called.
    public init() {}

    /// Resolves the descriptor's weights, downloading them if they are not on this Mac, and
    /// returns the directory to load from — or, for the four-bit variant, the release `build`
    /// packs next.
    ///
    /// What is already here is looked up rather than left to the vendored resolver, which knows
    /// only the layout `hf download` writes and would fetch a model Zephra itself downloaded
    /// again on every launch. Three places are looked at before anything is fetched: the packed
    /// variant, which makes the release unnecessary and may even have been deleted; the folder
    /// the user keeps models in; and the hub cache in either layout, read as a fallback and
    /// never written. `ZephraSnapshot`'s downloader does the fetching, and it is the only step
    /// that can report progress.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        acquisition: any ModelAcquisition,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            if let built = candidates.first(where: {
                LocalSnapshot.zImage.missingEntry(in: $0) == nil
            }) {
                return built
            }
            return try LocalSnapshot.zImage.verified(
                candidates.first ?? locations.built(descriptor), descriptor: descriptor)
        case .huggingFace:
            if descriptor.isBuiltLocally,
               let packed = LocalSnapshot.zImage.packedVariant(of: descriptor, in: locations)
            {
                return packed
            }
            let check = LocalSnapshot.zImage(for: descriptor)
            let here = check.downloadedRelease(of: descriptor, in: locations)
            if let here, locations.missingAdapters(of: descriptor).isEmpty { return here }
            let fetched = try await acquisition.fetch(
                descriptor, into: locations, release: here, onProgress: onProgress)
            return try check.verified(fetched, descriptor: descriptor)
        }
    }

    /// Reads the weights at `localPath` into memory.
    ///
    /// Whatever was loaded before is released first. Two Z-Image models are 13 GB each, so
    /// holding the old one while the new one arrives would put the machine into swap; the same
    /// backend serves every variant, and it serves one at a time.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        residency: WeightResidency,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        let pipeline = pipeline ?? ZImagePipeline()
        self.pipeline = pipeline
        do {
            try await pipeline.loadModel(modelSpec: localPath.path) { progress in
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
    }

    /// Runs one generation and returns the encoded PNG bytes.
    ///
    /// Cancellation is checked by the pipeline between denoising steps, so a cancelled task
    /// surfaces as `CancellationError`, which is passed through untouched rather than being
    /// reported as a failure.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
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
        // One throttle per run, so a frame is made at most every three quarters of a second
        // however fast the steps go by, and none at all when the environment has switched them
        // off. Nil rather than an always-refusing throttle: the loop then skips the check.
        var throttle = PreviewThrottle.environmentInterval.map(PreviewThrottle.init(interval:))
        let previewHandler: ZImagePipeline.PreviewHandler? =
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
            return try await pipeline.generateToMemory(
                request,
                progressHandler: { progress in
                    onProgress(ZImageProgressMapper.event(from: progress))
                },
                previewHandler: previewHandler
            )
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
    }
}
