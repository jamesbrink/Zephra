import Flux2
import Foundation
import ZephraCore
import ZephraSnapshot
import os

extension Flux2Backend {
    private static let logger = Logger(subsystem: "io.zephra", category: "download")

    /// Fetches the release into the hub cache, trying again when the transfer breaks. The hub
    /// client resumes each file from the bytes it already has, so a retry continues rather
    /// than starts over; only an answer that will not change — no such repository, a refused
    /// token — stops it early, and a refused token is named with where it came from, because
    /// the release is public and the token is the only thing that can be wrong.
    nonisolated(nonsending) func download(
        _ repoID: String,
        revision: String,
        patterns: [String],
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        HubNetworkPolicy.allowMeteredDownloads()
        do {
            return try await DownloadRetry.run(
                isPermanent: Flux2SnapshotDownload.isPermanent,
                onRetry: { attempt, error in
                    Self.logger.notice(
                        "download of \(repoID, privacy: .public) broke: \(error.readableMessage, privacy: .public); attempt \(attempt) follows"
                    )
                }
            ) {
                try await Flux2SnapshotDownload.snapshot(
                    repoID: repoID, revision: revision, patterns: patterns
                ) { progress in
                    onProgress(
                        DownloadProgressEvent(
                            completedFiles: progress.completedFiles,
                            totalFiles: progress.totalFiles,
                            fraction: progress.fraction,
                            bytesPerSecond: progress.bytesPerSecond))
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch where Flux2SnapshotDownload.isRefusal(error) {
            throw BackendError.downloadFailed(HubToken.refusalMessage())
        } catch {
            throw BackendError.downloadFailed(
                DownloadRetry.givingUpMessage(Flux2SnapshotDownload.reason(for: error)))
        }
    }
}
