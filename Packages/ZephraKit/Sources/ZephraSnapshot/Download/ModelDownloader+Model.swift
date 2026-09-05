import Foundation
import ZephraCore
import os

extension ModelDownloader {
    private static let logger = Logger(subsystem: "io.zephra", category: "download")

    /// Fetches `descriptor`'s release, and every adapter merged into it, into `locations`,
    /// trying again when the transfer breaks, and reports what stopped it in words a person can
    /// act on. Returns the directory the release landed in.
    ///
    /// This is the one call each backend makes: every family downloads the same way, so the
    /// retry, the classification and the message are here rather than three times over. Only an
    /// answer that will not change — no such repository, a refusal — stops the tries early;
    /// everything else resumes from the bytes on disk, which is also what Try again does.
    /// Cancellation instead removes unfinished writable downloads before returning; completed
    /// repositories and read-only cached releases are retained.
    public func fetch(
        _ descriptor: ModelDescriptor,
        into locations: ModelLocations,
        release existing: URL? = nil,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL {
        guard case .huggingFace(let repoID, let revision, let patterns) = descriptor.source else {
            throw BackendError.modelNotAvailable(descriptor.fullName)
        }
        // A release already on this Mac — in the models folder or the hub cache — is kept,
        // and only what is missing moves: thirty gigabytes are never fetched for want of an
        // adapter of two.
        let release = existing ?? locations.downloads(repoID: repoID)
        let releasePart = existing == nil
            ? [RepositoryDownload(
                repoID: repoID, revision: revision, patterns: patterns, destination: release)]
            : []
        let parts = releasePart
            + locations.missingAdapters(of: descriptor).map {
                RepositoryDownload(
                    repoID: $0.repoID, revision: $0.revision, patterns: [$0.file],
                    destination: locations.adapter($0))
            }
        if parts.isEmpty { return release }
        try ModelDirectoryAccess.prepare(locations.root)
        do {
            try await DownloadRetry.run(
                isPermanent: { ($0 as? ModelDownloadError)?.isPermanent ?? false },
                onRetry: { attempt, error in
                    Self.logger.notice(
                        "download of \(repoID, privacy: .public) broke: \(error.readableMessage, privacy: .public); attempt \(attempt) follows"
                    )
                }
            ) {
                try await download(parts, onProgress: onProgress)
            }
            return release
        } catch let error as CancellationError {
            do {
                try Self.discardUnfinished(parts, under: locations.root)
            } catch {
                throw BackendError.downloadFailed(
                    "The download stopped, but its partial files could not be removed: \(error.localizedDescription)")
            }
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
