import Foundation
import ZephraCore

/// The running total a download's progress events are made from.
///
/// Two things it does that a bare fraction would not. Progress is weighted by bytes, not by
/// files: a repository is one twelve-gigabyte shard and a dozen small configs, and counting
/// files would sit at 11/12 for the whole transfer. And events are held to one every fifth of a
/// second, because a chunk arrives every few milliseconds and each event ends up on the main
/// actor.
struct DownloadTally {
    /// How many files the download covers.
    let totalFiles: Int
    /// How many bytes they add up to, as the listing counted them.
    let totalBytes: Int64
    /// Files finished, including the ones that were already on disk.
    private(set) var completedFiles = 0
    /// Bytes on disk for this download, including the ones that were there when it started.
    private(set) var completedBytes: Int64 = 0

    /// The last few readings, for a rate that is neither the whole transfer's average nor the
    /// jitter of one chunk.
    private var samples: [(at: ContinuousClock.Instant, bytes: Int64)] = []
    private var lastReport: ContinuousClock.Instant?

    /// How long a rate is averaged over.
    private static let window = Duration.seconds(5)
    /// The shortest gap between two events.
    private static let interval = Duration.milliseconds(200)

    init(totalFiles: Int, totalBytes: Int64) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
    }

    /// Counts bytes that have landed on disk.
    mutating func advance(by bytes: Int64) {
        completedBytes += bytes
    }

    /// Un-counts bytes that turned out not to be usable: a partial file the server would not
    /// resume, which has to be fetched from the start.
    mutating func discard(_ bytes: Int64) {
        completedBytes -= bytes
    }

    /// Counts one file as finished.
    mutating func finishFile() {
        completedFiles += 1
    }

    /// The event to report now, or nil when the last one was too recent. `force` is for the
    /// moments that must be seen whatever the timing: the start, and each finished file.
    mutating func report(force: Bool = false, now: ContinuousClock.Instant = .now)
        -> DownloadProgressEvent?
    {
        samples.append((now, completedBytes))
        samples.removeAll { now - $0.at > Self.window }
        if !force, let lastReport, now - lastReport < Self.interval { return nil }
        lastReport = now
        return DownloadProgressEvent(
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            fraction: totalBytes > 0
                ? min(1, Double(completedBytes) / Double(totalBytes))
                : (totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0),
            bytesPerSecond: rate(now: now)
        )
    }

    /// Bytes a second over the window, or nil until there is enough of a window to divide by.
    private func rate(now: ContinuousClock.Instant) -> Double? {
        guard let first = samples.first, first.at < now else { return nil }
        let seconds = (now - first.at).components
        let elapsed = Double(seconds.seconds) + Double(seconds.attoseconds) / 1e18
        guard elapsed >= 0.5 else { return nil }
        return Double(completedBytes - first.bytes) / elapsed
    }
}
