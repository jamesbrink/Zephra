import Foundation

extension ModelDownloader {
    /// The file a download in flight keeps its commit in, beside the files themselves. Written
    /// when the transfer starts and removed when its last file lands, so a directory holding
    /// one is a download that has not finished, whatever its files say.
    static func pin(in destination: URL) -> URL {
        destination.appending(path: ".zephra-revision")
    }

    /// The file a finished download keeps its commit in, so a later transfer into the same
    /// folder knows whether what is there is the commit it wants.
    static func completed(in destination: URL) -> URL {
        destination.appending(path: ".zephra-commit")
    }

    /// Makes `destination` safe to fill at `sha`: a folder finished at another commit is
    /// emptied first. A shard whose tensors changed shape-for-shape keeps its size, and the
    /// size is all a file is otherwise trusted on, so nothing from another commit may stay to
    /// be taken for part of this one. A folder with no record — `hf download`'s, or an older
    /// Zephra's — is trusted on size, as it always was.
    static func prepare(_ destination: URL, for sha: String) throws {
        let files = FileManager.default
        let record = completed(in: destination)
        guard let before = try? String(contentsOf: record, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), before != sha
        else { return }
        // The record goes last. Emptied in any other order, a process that dies part-way
        // leaves a folder with no record and a same-sized shard from the other commit still
        // in it, which the next try would trust on size.
        let folder = destination.path(percentEncoded: false)
        for entry in (try? files.contentsOfDirectory(atPath: folder)) ?? []
        where entry != record.lastPathComponent {
            try files.removeItem(at: destination.appending(path: entry))
        }
        try files.removeItem(at: record)
    }

    /// The commit this transfer is pinned to: the one it started at, when it is resuming, or
    /// what the repository's `revision` names right now, written down for next time.
    ///
    /// A catalog entry names `main`, which moves. A download that takes hours, or that is
    /// resumed a week later, would otherwise list files from one commit and fetch them from
    /// another — configs, shards and an adapter that never belonged together, kept on the
    /// strength of their sizes. So the name is resolved once, at the start, and every listing
    /// and every file request of the transfer names the commit rather than the branch.
    func pinnedRevision(
        for part: RepositoryDownload, on session: URLSession
    ) async throws -> String {
        let pin = Self.pin(in: part.destination)
        if let pinned = try? String(contentsOf: pin, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !pinned.isEmpty
        {
            return pinned
        }
        let sha = try await commit(of: part.repoID, revision: part.revision, on: session)
        try FileManager.default.createDirectory(
            at: part.destination, withIntermediateDirectories: true)
        try Self.prepare(part.destination, for: sha)
        try sha.write(to: pin, atomically: true, encoding: .utf8)
        return sha
    }

    /// Asks the hub which commit `revision` names.
    private func commit(of repoID: String, revision: String, on session: URLSession) async throws
        -> String
    {
        let url = host.appending(path: "api/models/\(repoID)/revision/\(revision)")
        let (data, _) = try await load(url, on: session, repoID: repoID)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = object["sha"] as? String, !sha.isEmpty
        else { throw ModelDownloadError.unreadableListing }
        return sha
    }
}
