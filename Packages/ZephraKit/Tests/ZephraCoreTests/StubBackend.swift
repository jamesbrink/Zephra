import Foundation
import ZephraCore

/// The least a type can do and still be an `ImageGenerationBackend`. Core has no engine to run
/// one, so this exists only to give `BackendRegistry` something to hand back.
final class StubBackend: ImageGenerationBackend {
    static let backendID: BackendID = "stub"

    /// The identifier this stub claims to have loaded, set by whoever built it.
    let loadedModelID: String?

    init(loadedModelID: String? = nil) {
        self.loadedModelID = loadedModelID
    }

    func availability(
        of descriptor: ModelDescriptor, locations: ModelLocations
    ) async -> ModelAvailability {
        .available
    }

    func ensureAvailable(
        _ descriptor: ModelDescriptor,
        locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        URL(filePath: NSTemporaryDirectory())
    }

    func load(
        _ descriptor: ModelDescriptor,
        at localPath: URL,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws {}

    func generate(
        _ settings: GenerationSettings,
        onProgress: @escaping (GenerationProgressEvent) -> Void
    ) async throws -> Data {
        Data()
    }

    func unload() {}
}
