import Foundation

/// One repository's directory in the hub cache, in whichever of the two layouts it was
/// written, and the snapshot inside it a load would open.
public struct HubRepository: Hashable, Sendable {
    /// Which tool wrote the directory, which decides where the snapshot is inside it.
    public enum Layout: Hashable, Sendable {
        /// `models--<org>--<repo>/snapshots/<commit>/`, with `refs/<revision>` naming the
        /// commit and every file a link into `blobs/`. What `hf download` writes.
        case hub
        /// `models/<org>/<repo>/`, the directory itself the snapshot, with the transfer's
        /// bookkeeping under `.cache/huggingface/download/`. What an older Zephra's hub client
        /// wrote; nothing writes it now.
        case flat
    }

    /// The repository directory: what a storage listing measures and a deletion removes.
    public let url: URL
    public let layout: Layout

    /// The complete snapshot for `revision`, or nil when there is none.
    ///
    /// In the `hub` layout the cache records where a branch points in `refs/<revision>`, and
    /// that commit is the only snapshot a load would open: an older one left by a previous
    /// revision is still a complete directory, so answering with it would promise weights that
    /// will never be read. When the refs say nothing about this revision, one snapshot is
    /// unambiguous and two are a guess, so a lone snapshot answers and anything else reads as
    /// needing a download. The `flat` layout records no revision, so it answers for any.
    ///
    /// Either way a snapshot counts only if `HubSnapshotCheck` says it is complete, which is
    /// what tells a finished download apart from an abandoned one.
    public func snapshot(revision: String = "main") -> URL? {
        guard let candidate = candidate(revision: revision), HubSnapshotCheck.isComplete(candidate)
        else { return nil }
        return candidate
    }

    /// One file of the snapshot for `revision`, or nil when it is not here. Asked about a file
    /// rather than the snapshot because an adapter's repository holds no config to satisfy
    /// `HubSnapshotCheck`, and one finished file is all that is wanted of it. Either tool
    /// puts the file in place only once it is whole, so being there is being finished.
    public func file(_ path: String, revision: String = "main") -> URL? {
        guard let candidate = candidate(revision: revision) else { return nil }
        let file = candidate.appending(path: path)
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    /// The directory the snapshot for `revision` would be, complete or not.
    private func candidate(revision: String) -> URL? {
        switch layout {
        case .hub:
            let snapshots = url.appending(path: "snapshots")
            return commit(of: revision).map { snapshots.appending(path: $0) }
                ?? Self.onlySnapshot(in: snapshots)
        case .flat:
            return url
        }
    }

    /// Whether a load could open what is here.
    public var isComplete: Bool { snapshot() != nil }

    /// The commit `revision` names: the contents of `refs/<revision>`, or `revision` itself when
    /// it already names a snapshot directory, which is how a revision pinned to a hash arrives.
    private func commit(of revision: String) -> String? {
        let reference = url.appending(path: "refs").appending(path: revision)
        if let contents = try? String(contentsOf: reference, encoding: .utf8) {
            let commit = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !commit.isEmpty { return commit }
        }
        let pinned = url.appending(path: "snapshots").appending(path: revision)
        return HubCache.isDirectory(pinned) ? revision : nil
    }

    /// The one snapshot in the cache, when there is exactly one. Several with no ref to choose
    /// between them is ambiguous, and guessing is what this whole lookup exists to avoid.
    private static func onlySnapshot(in snapshots: URL) -> URL? {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: snapshots, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let directories = contents.filter { HubCache.isDirectory($0) }
        return directories.count == 1 ? directories.first : nil
    }
}
