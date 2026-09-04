import Foundation

extension ModelDownloader {
    /// The file a download in flight keeps its commit in, beside the files themselves. Written
    /// when the transfer starts and removed when its last file lands, so a directory holding
    /// one is a download that has not finished, whatever its files say.
    static func pin(in destination: URL) -> URL {
        destination.appending(path: ".zephra-revision")
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
