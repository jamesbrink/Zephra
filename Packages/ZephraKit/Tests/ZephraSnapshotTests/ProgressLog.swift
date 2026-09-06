import Foundation
import ZephraCore

/// The progress events one download reported, so a test can look at the last one.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DownloadProgressEvent] = []

    func record(_ event: DownloadProgressEvent) {
        lock.withLock { events.append(event) }
    }

    var first: DownloadProgressEvent? { lock.withLock { events.first } }

    var last: DownloadProgressEvent? { lock.withLock { events.last } }
}
