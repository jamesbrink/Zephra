import Foundation
import ZephraCore

/// Mutable request bookkeeping confined to ModelDownloads' main actor.
@MainActor
final class DownloadRequest {
    let id = UUID()
    let model: ModelDescriptor
    let locations: ModelLocations
    var task: Task<URL, any Error>?
    var borrowers = 0
    var progress: (@MainActor (DownloadProgressEvent) -> Void)?
    var settled = false
    var released = false
    var discard = false
    var stopped: ModelDownload.Status?

    init(_ model: ModelDescriptor, _ locations: ModelLocations) {
        self.model = model
        self.locations = locations
    }
}
