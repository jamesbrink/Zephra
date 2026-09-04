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
            // Every file of this part is down at the commit it was pinned to: the pin goes,
            // the commit is written down for the next transfer into this folder to compare
            // against, and the directory is a finished download from here on.
            try part.revision.write(
                to: Self.completed(in: part.destination), atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: Self.pin(in: part.destination))
            Self.dropHubPartials(in: part.destination)
        }
    }

    /// Removes what an interrupted `hf download --local-dir` into this same folder left
    /// behind: its `.incomplete` files under `.cache/huggingface/download`. Every file this
    /// transfer listed is whole now, and `HubSnapshotCheck` would otherwise hold the folder
    /// incomplete for good on the strength of a partial nothing will ever finish. Only the
    /// partials go; the metadata `hf` keeps beside them is left for it.
    private static func dropHubPartials(in destination: URL) {
        let bookkeeping = destination.appending(path: ".cache/huggingface/download")
        for file in HubSnapshotCheck.incompleteFiles(in: bookkeeping)
        where file.pathExtension == "incomplete" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// What each part actually holds: its revision pinned to a commit, its repository listed
    /// at that commit, then filtered by its globs. A part that names a repository the hub has
    /// not got, or whose globs match nothing in it, stops the whole download — a catalog
    /// written against a repository that has been rearranged is not something to half-fetch.
    private func listing(
        of parts: [RepositoryDownload], on session: URLSession
    ) async throws -> [(part: RepositoryDownload, files: [RepositoryFile])] {
        var work: [(part: RepositoryDownload, files: [RepositoryFile])] = []
        for named in parts {
            let part = named.pinned(to: try await pinnedRevision(for: named, on: session))
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
