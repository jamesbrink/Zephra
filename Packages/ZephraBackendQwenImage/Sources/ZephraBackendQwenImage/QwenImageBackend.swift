import Foundation
import QwenImage
import ZephraCore
import ZephraSnapshot

/// Runs Qwen-Image family models through the MLX pipeline.
///
/// Not Sendable: it owns a pipeline holding MLX arrays that stay on one thread. The engine layer
/// confines it to a serial executor.
public nonisolated final class QwenImageBackend: ImageGenerationBackend {
    /// The model family this backend serves.
    public static let backendID = BackendID.qwenImage

    /// The descriptor identifier currently in memory, or nil when nothing is loaded.
    public private(set) var loadedModelID: String?

    private let pipeline = QwenImagePipeline()
    private var loadedDescriptor: ModelDescriptor?

    /// Creates an idle backend. No weights are touched until `ensureAvailable` is called.
    public init() {}

    /// Resolves the descriptor's weights and returns the local snapshot directory.
    ///
    /// Qwen-Image ships only in full precision, at 57.7 GB, and Zephra runs a quantized build
    /// made on this Mac. So there is nothing to download: the descriptor names a local directory
    /// and this reports clearly when it is not there yet.
    nonisolated(nonsending) public func ensureAvailable(
        _ descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        switch descriptor.source {
        case .localDirectory(let directory):
            return try LocalSnapshot.qwenImage.verified(directory, descriptor: descriptor)
        case .huggingFace:
            throw BackendError.modelNotAvailable(descriptor.fullName)
        }
    }

    /// Whether the weights are on this Mac, read from the disk alone.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory(let directory):
            guard let missing = LocalSnapshot.qwenImage.missingEntry(in: directory) else {
                return .available
            }
            return .missing(reason: "Not built yet: \(missing) is missing. Run `make quantize-qwen`.")
        case .huggingFace:
            return .missing(reason: "Qwen-Image is built locally, not downloaded.")
        }
    }

    /// Reads the weights at `localPath` into memory, releasing whatever was there first.
    nonisolated(nonsending) public func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        do {
            try pipeline.loadModel(at: localPath) { progress in
                onProgress(QwenImageProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.loadFailed(error.readableMessage)
        }
        loadedModelID = descriptor.id
        loadedDescriptor = descriptor
    }

    /// Runs one generation and returns the encoded PNG bytes.
    nonisolated(nonsending) public func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
        guard let descriptor = loadedDescriptor else {
            throw BackendError.loadFailed("No model is loaded.")
        }
        do {
            return try pipeline.generate(
                QwenImageRequestMapper.request(for: settings, descriptor: descriptor)
            ) { progress in
                onProgress(QwenImageProgressMapper.event(from: progress))
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw BackendError.generationFailed(error.readableMessage)
        }
    }

    /// Drops the weights and clears the GPU cache, leaving the backend reusable.
    public func unload() {
        pipeline.unloadModel()
        loadedModelID = nil
        loadedDescriptor = nil
    }
}
