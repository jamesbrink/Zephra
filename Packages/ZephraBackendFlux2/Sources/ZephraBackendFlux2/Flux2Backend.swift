import Flux2
import Foundation
import ZephraCore
import ZephraSnapshot

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
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {
        if loadedModelID != nil { unload() }
        do {
            try pipeline.loadModel(at: localPath) { progress in
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
        do {
            return try pipeline.generate(
                Flux2RequestMapper.request(for: settings, descriptor: descriptor)
            ) { progress in
                onProgress(Flux2ProgressMapper.event(from: progress))
            }
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

    /// Where the packed variant for `descriptor` lives, built or not: the catalog's local models
    /// directory, named after the descriptor, which is the convention every locally built
    /// variant follows.
    static func packedDirectory(for descriptor: ModelDescriptor) -> URL {
        ModelCatalog.localModelsDirectory.appending(path: descriptor.id, directoryHint: .isDirectory)
    }
}
