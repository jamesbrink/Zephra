import Foundation
import ZephraCore
import ZephraSnapshot
import ZImage
import os

extension ZImageBackend {
    private static let logger = Logger(subsystem: "io.zephra", category: "download")

    /// Fetches the repository into the hub cache through the vendored resolver, trying again
    /// when the transfer breaks. The hub client resumes each file from the bytes it already
    /// has, so a retry continues rather than starts over; only an answer that will not change
    /// — no such repository, a refused token — stops it early.
    nonisolated(nonsending) func download(
        _ repoID: String,
        revision: String,
        filePatterns: [String],
        descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        HubNetworkPolicy.allowMeteredDownloads()
        do {
            return try await DownloadRetry.run(
                isPermanent: ZImageErrorMapping.isPermanent,
                onRetry: { attempt, error in
                    Self.logger.notice(
                        "download of \(repoID, privacy: .public) broke: \(error.readableMessage, privacy: .public); attempt \(attempt) follows"
                    )
                }
            ) {
                try await ModelResolution.resolve(
                    modelSpec: repoID,
                    defaultRevision: revision,
                    filePatterns: filePatterns,
                    progressHandler: { progress in
                        onProgress(
                            DownloadProgressEvent(
                                completedFiles: Int(progress.completedUnitCount),
                                totalFiles: Int(progress.totalUnitCount),
                                fraction: progress.fractionCompleted,
                                bytesPerSecond: nil
                            )
                        )
                    }
                )
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ModelResolutionError {
            throw ZImageErrorMapping.downloadError(error, descriptor: descriptor)
        } catch {
            throw BackendError.downloadFailed(DownloadRetry.givingUpMessage(error.readableMessage))
        }
    }
}
