import Foundation
import ZephraCore

/// State for one physical writer, including preflight shared by every consumer.
final class RepositoryTransfer {
    let part: RepositoryDownload
    var owners: Set<UUID> = []
    var preparation: Task<[(part: RepositoryDownload, files: [RepositoryFile])], any Error>?
    var work: [(part: RepositoryDownload, files: [RepositoryFile])]?
    var task: Task<Void, Never>?
    var result: Result<Void, any Error>?
    var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    var progress: DownloadProgressEvent?
    var listeners: [UUID: @Sendable (DownloadProgressEvent) -> Void] = [:]
    var remainingBytes: Int64 = 0
    var volume: String?

    init(_ part: RepositoryDownload) { self.part = part }
}
