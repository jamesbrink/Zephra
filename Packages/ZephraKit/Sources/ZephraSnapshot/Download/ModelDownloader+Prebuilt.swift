import Foundation
import ZephraCore
import os

extension ModelDownloader {
    private static let logger = Logger(subsystem: "io.zephra", category: "download")

    /// Fetches `descriptor`'s packed variant from its mirror into `locations.built(descriptor)`
    /// and returns that directory, or nil when it could not — the mirror has no index, or none
    /// naming this variant as the catalog describes it, or the host is down, or the transfer
    /// broke and stayed broken — so the caller fetches the release and builds instead, the way
    /// it did before there was a mirror. The mirror is a shortcut and nothing more: no failure
    /// of it is shown to anyone, only logged, because the path behind it always works.
    ///
    /// The files land in the built directory's `.partial` sibling, each checked against the
    /// digest the index gave, and the directory is renamed into place only when the last is
    /// down: a variant with files still to come is never where a loader would find it. A
    /// transfer that breaks is tried again from the bytes on disk, as a release is, and what
    /// is on disk is kept for a later try; a stopped one has its partial removed, as the
    /// standalone `fetch` does.
    public func fetchPrebuilt(
        _ descriptor: ModelDescriptor,
        into locations: ModelLocations,
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws -> URL? {
        guard let part = RepositoryDownload.prebuilt(descriptor, in: locations) else { return nil }
        try ModelDirectoryAccess.prepare(locations.root)
        do {
            try await DownloadRetry.run(
                isPermanent: { ($0 as? ModelDownloadError)?.isPermanent ?? false },
                onRetry: { attempt, error in
                    Self.logger.notice(
                        "mirror fetch of \(descriptor.id, privacy: .public) broke: \(error.readableMessage, privacy: .public); attempt \(attempt) follows"
                    )
                }
            ) {
                try await download([part], onProgress: onProgress)
            }
            return try Self.publishPrebuilt(part.destination, as: locations.built(descriptor))
        } catch let error as CancellationError {
            try Self.discardUnfinished([part], under: locations.root)
            throw error
        } catch {
            Self.logger.notice(
                "\(descriptor.id, privacy: .public) was not fetched from the mirror (\(error.readableMessage, privacy: .public)); building it here instead"
            )
            return nil
        }
    }

    /// Where a variant is fetched to before it is whole: the `.partial` sibling of where it
    /// will live, the same directory a build writes into, so a stale one of either kind is
    /// replaced by whichever runs next rather than mistaken for a model.
    static func prebuiltPartial(of descriptor: ModelDescriptor, in locations: ModelLocations) -> URL {
        let built = locations.built(descriptor)
        return built.deletingLastPathComponent()
            .appending(path: built.lastPathComponent + ".partial", directoryHint: .isDirectory)
    }

    /// Renames a finished `.partial` into place, replacing whatever `built` held: the only
    /// thing that can be there is a variant `packedVariant` already refused, since a matching
    /// one would have been loaded without a fetch.
    static func publishPrebuilt(_ partial: URL, as built: URL) throws -> URL {
        let files = FileManager.default
        guard !isLink(partial), !isLink(built) else {
            throw BackendError.downloadFailed("The models folder holds a link where a variant should be.")
        }
        if files.fileExists(atPath: built.path(percentEncoded: false)) {
            try files.removeItem(at: built)
        }
        try files.moveItem(at: partial, to: built)
        return built
    }
}
