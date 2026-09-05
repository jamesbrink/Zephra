import Foundation
import ZephraCore

/// A private, unloaded backend for family-specific disk checks. Never shares a mutable
/// backend with inference, and never calls build/load/generate on this instance.
actor ModelResolution {
    func resolve(
        _ model: ModelDescriptor, registry: BackendRegistry, locations: ModelLocations,
        acquisition: any ModelAcquisition,
        progress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        let backend = try registry.make(model)
        return try await backend.ensureAvailable(model, locations: locations,
            acquisition: acquisition, onProgress: progress)
    }
}
