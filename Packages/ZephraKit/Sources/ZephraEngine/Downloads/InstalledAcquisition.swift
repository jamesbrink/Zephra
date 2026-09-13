import Foundation
import ZephraCore

/// A strict queued job may resolve local files but can never start a transfer.
struct InstalledAcquisition: ModelAcquisition {
    func fetch(_ descriptor: ModelDescriptor, into locations: ModelLocations, release: URL?,
               onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void) async throws -> URL {
        throw BackendError.loadFailed("The installed model is no longer available. Nothing was downloaded.")
    }
    func fetchPrebuilt(_ descriptor: ModelDescriptor, into locations: ModelLocations,
                       onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void) async throws -> URL? {
        throw BackendError.loadFailed("The installed model is no longer available. Nothing was downloaded.")
    }
}
