import Foundation

/// Disk acquisition injected into a backend's family-specific snapshot checks.
/// Implementations own transfers; cancellation of a UI waiter need not stop shared bytes.
public protocol ModelAcquisition: Sendable {
    func fetch(
        _ descriptor: ModelDescriptor, into locations: ModelLocations, release: URL?,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL
}
