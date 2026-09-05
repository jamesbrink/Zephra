import Foundation
import ZephraCore

/// A model's lease on repository files, retained through family validation and build.
public struct TransferAcquisition: ModelAcquisition {
    public let id: UUID
    let pool: ModelTransfers

    public init(id: UUID, pool: ModelTransfers) {
        self.id = id
        self.pool = pool
    }

    public func fetch(
        _ descriptor: ModelDescriptor, into locations: ModelLocations, release: URL?,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        try await pool.fetch(id, descriptor, locations, release: release, onProgress: onProgress)
    }
}
