import Foundation
import ZephraCore

extension ModelDownloader {
    /// Fetches every part of a download — the release, and any adapter merged into it — as one
    /// transfer.
    ///
    /// Every part is listed before a single byte is fetched, so an adapter repository that has
    /// moved is a failure in a second rather than after fifty-seven gigabytes. And every
    /// listing feeds one tally, so the fraction and the file count are the whole download's:
    /// otherwise a release and the adapter merged into it would be two bars, each running to a
    /// hundred per cent, the second of them after the first had said it was finished.
    public func download(
        _ parts: [RepositoryDownload],
        onProgress: @escaping @Sendable (DownloadProgressEvent) -> Void
    ) async throws {
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }

        let work = try await listing(of: parts, on: session)
        var tally = DownloadTally(
            totalFiles: work.reduce(0) { $0 + $1.files.count },
            totalBytes: work.reduce(0) { $0 + $1.files.reduce(0) { $0 + $1.bytes } })
        for (part, files) in work {
            try FileManager.default.createDirectory(
                at: part.destination, withIntermediateDirectories: true)
            for file in files { tally.advance(by: bytesOnDisk(of: file, in: part.destination)) }
        }
        if let event = tally.report(force: true) { onProgress(event) }

        for (part, files) in work {
            for file in files {
                try Task.checkCancellation()
                try await fetch(
                    file, from: part.repoID, revision: part.revision, into: part.destination,
                    on: session, tally: &tally, onProgress: onProgress)
                tally.finishFile()
                if let event = tally.report(force: true) { onProgress(event) }
            }
        }
    }

    /// What each part actually holds: its repository listed, then filtered by its globs. A part
    /// that names a repository the hub has not got, or whose globs match nothing in it, stops
    /// the whole download — a catalog written against a repository that has been rearranged is
    /// not something to half-fetch.
    private func listing(
        of parts: [RepositoryDownload], on session: URLSession
    ) async throws -> [(part: RepositoryDownload, files: [RepositoryFile])] {
        var work: [(part: RepositoryDownload, files: [RepositoryFile])] = []
        for part in parts {
            let listed = try await listing(of: part.repoID, revision: part.revision, on: session)
            guard !listed.isEmpty else {
                throw ModelDownloadError.repositoryNotFound(repoID: part.repoID)
            }
            let files = listed.filter { FilePattern.matchesAny($0.path, patterns: part.patterns) }
            guard !files.isEmpty else {
                throw ModelDownloadError.nothingMatched(repoID: part.repoID)
            }
            work.append((part, files))
        }
        return work
    }
}
