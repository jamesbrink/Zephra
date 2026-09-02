import Foundation
import ZephraCore
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

    /// Says whether the weights are already on this Mac, reading the disk and nothing else.
    ///
    /// A Hugging Face model is looked up in the hub cache the loader itself would use; a local
    /// directory is checked for the entries the pipeline will open. Neither path downloads, and
    /// neither disturbs whatever is loaded, so a picker can label the whole catalog for free.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory(let directory):
            guard let missing = ZImageLocalSnapshot.missingEntry(in: directory) else {
                return .available
            }
            return .missing(
                reason: """
                    \(descriptor.fullName) is not at \
                    \(directory.path(percentEncoded: false)): missing \(missing).
                    """
            )
        case .huggingFace(let repoID, _, _):
            guard ZImageHubCache.snapshot(of: repoID) != nil else {
                return .needsDownload(bytes: descriptor.downloadBytes)
            }
            return .available
        }
    }

    /// Resolves the descriptor's weights, downloading them if the cache does not already
    /// hold them, and returns the local snapshot directory.
    ///
    /// This is the only step that can report download progress: the pipeline's own loader
    /// resolves the snapshot silently, so Zephra resolves it up front and then hands the
    /// resulting path to `load` as a plain local directory.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory(let directory):
            return try ZImageLocalSnapshot.verified(directory, descriptor: descriptor)
        case .huggingFace(let repoID, let revision, let filePatterns):
            return try await download(repoID, revision: revision, filePatterns: filePatterns,
                                      descriptor: descriptor, onProgress: onProgress)
        }
    }

    private nonisolated(nonsending) func download(
        _ repoID: String,
        revision: String,
        filePatterns: [String],
        descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        do {
            return try await ModelResolution.resolve(
                modelSpec: repoID,
                defaultRevision: revision,
                filePatterns: filePatterns,
                progressHandler: { progress in
                    onProgress(
                        DownloadProgressEvent(
                            completedFiles: Int(progress.completedUnitCount),
                            totalFiles: Int(progress.totalUnitCount),
                            fraction: progress.fractionCompleted,
                            bytesPerSecond: nil
                        )
                    )
                }
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as ModelResolutionError {
            throw ZImageErrorMapping.downloadError(error, descriptor: descriptor)
        } catch {
            throw BackendError.downloadFailed(ZImageErrorMapping.message(error))
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
            throw BackendError.loadFailed(ZImageErrorMapping.message(error))
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
        let request = ZImageRequestMapper.request(
            for: settings,
            descriptor: descriptor,
            snapshot: snapshot
        )
        do {
            return try await pipeline.generateToMemory(request) { progress in
                onProgress(ZImageProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(ZImageErrorMapping.message(error))
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
