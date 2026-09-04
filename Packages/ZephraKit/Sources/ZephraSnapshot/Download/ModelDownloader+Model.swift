import Foundation
import ZephraCore
import os

extension ModelDownloader {
    private static let logger = Logger(subsystem: "io.zephra", category: "download")

    /// Fetches `descriptor`'s repository into `locations`, trying again when the transfer
    /// breaks, and reports what stopped it in words a person can act on.
    ///
    /// This is the one call each backend makes: every family downloads the same way, so the
    /// retry, the classification and the message are here rather than three times over. Only an
    /// answer that will not change — no such repository, a refusal — stops the tries early;
    /// everything else resumes from the bytes on disk, which is also what Try again does.
    public func fetch(
        _ descriptor: ModelDescriptor,
        into locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        guard case .huggingFace(let repoID, let revision, let patterns) = descriptor.source else {
            throw BackendError.modelNotAvailable(descriptor.fullName)
        }
        do {
            return try await DownloadRetry.run(
                isPermanent: { ($0 as? ModelDownloadError)?.isPermanent ?? false },
                onRetry: { attempt, error in
                    Self.logger.notice(
                        "download of \(repoID, privacy: .public) broke: \(error.readableMessage, privacy: .public); attempt \(attempt) follows"
                    )
                }
            ) {
                try await download(
                    repoID: repoID, revision: revision, patterns: patterns,
                    into: locations.downloads(repoID: repoID), onProgress: onProgress)
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as ModelDownloadError {
            throw Self.backendError(error, descriptor: descriptor)
        } catch {
            throw BackendError.downloadFailed(
                DownloadRetry.givingUpMessage(error.readableMessage))
        }
    }

    /// A download failure as the interface should show it: a repository that is not there is
    /// the model being unavailable, and everything else is a transfer that stopped, with the
    /// note that trying again picks up where it left off.
    static func backendError(_ error: ModelDownloadError, descriptor: ModelDescriptor)
        -> BackendError
    {
        switch error {
        case .repositoryNotFound: .modelNotAvailable(descriptor.fullName)
        default: .downloadFailed(DownloadRetry.givingUpMessage(error.reason))
        }
    }
}
