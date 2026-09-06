#if DEBUG
import Foundation
import ZephraCore

/// Exercises the real download/store/UI path against a loopback fixture without loading
/// model weights. Installed only by the composition root's explicit Debug exercise hook.
nonisolated final class DownloadExerciseBackend: ImageGenerationBackend {
    static let backendID = BackendID.zImage
    private(set) var loadedModelID: String?

    func availability(of model: ModelDescriptor, locations: ModelLocations) async -> ModelAvailability {
        .needsDownload(bytes: 8 << 20)
    }

    func ensureAvailable(
        _ model: ModelDescriptor, locations: ModelLocations, acquisition: any ModelAcquisition,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        try await acquisition.fetch(model, into: locations, release: nil, onProgress: onProgress)
    }

    func load(_ model: ModelDescriptor, at path: URL, residency: WeightResidency,
              onProgress: @escaping (GenerationProgressEvent) -> Void) async throws {
        onProgress(GenerationProgressEvent(phase: .preparing, fraction: 0))
        try await Task.sleep(for: .milliseconds(300))
        loadedModelID = model.id
    }

    func generate(_ settings: GenerationSettings,
                  onProgress: @escaping (GenerationProgressEvent) -> Void) async throws -> GeneratedMedia {
        try await Task.sleep(for: .milliseconds(300))
        return .image(png: Data())
    }

    func unload() { loadedModelID = nil }
}
#endif
