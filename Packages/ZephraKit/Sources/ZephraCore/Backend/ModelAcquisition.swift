import Foundation

/// Disk acquisition injected into a backend's family-specific snapshot checks.
/// Implementations own transfers; cancellation of a UI waiter need not stop shared bytes.
public protocol ModelAcquisition: Sendable {
    func fetch(
        _ descriptor: ModelDescriptor, into locations: ModelLocations, release: URL?,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL

    /// Fetches the packed variant of `descriptor` from its mirror into `locations.built`, and
    /// returns that directory — or nil when the mirror does not publish this variant as the
    /// catalog describes it, which is the caller's cue to fetch the release and build instead.
    /// A transfer that breaks throws, the way `fetch` does, and Try Again resumes it.
    func fetchPrebuilt(
        _ descriptor: ModelDescriptor, into locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL?
}
