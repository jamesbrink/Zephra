import Synchronization
import ZephraCore

/// Progress of a release and its adapters, shared across repository callback queues.
final class TransferProgress: Sendable {
    private let events = Mutex<[RepositoryDownload: DownloadProgressEvent]>([:])
    private let parts: [RepositoryDownload]
    private let emit: @Sendable (DownloadProgressEvent) -> Void

    init(parts: [RepositoryDownload], emit: @escaping @Sendable (DownloadProgressEvent) -> Void) {
        self.parts = parts
        self.emit = emit
    }

    func update(_ part: RepositoryDownload, _ event: DownloadProgressEvent) {
        let values = events.withLock { events in
            events[part] = event
            return Array(events.values)
        }
        let total = values.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }
        let completed = values.reduce(Int64(0)) { $0 + ($1.completedBytes ?? 0) }
        emit(DownloadProgressEvent(
            completedFiles: values.reduce(0) { $0 + $1.completedFiles },
            totalFiles: values.reduce(0) { $0 + $1.totalFiles },
            fraction: total > 0 ? Double(completed) / Double(total)
                : values.reduce(0) { $0 + $1.fraction } / Double(max(1, parts.count)),
            bytesPerSecond: values.compactMap(\.bytesPerSecond).reduce(0, +),
            completedBytes: completed, totalBytes: total))
    }
}
