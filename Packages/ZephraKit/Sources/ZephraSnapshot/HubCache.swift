import Foundation

/// Finds what the Hugging Face hub cache already holds, without opening a connection.
///
/// This is what lets a model picker say "13.3 GB download" without starting one, so it reads the
/// disk and nothing else. It is model-agnostic: every answer comes from the repository id and
/// the revision it is given.
///
/// A pipeline's own resolver usually performs the same lookup on its way to a download, but as a
/// private step that cannot be asked about, and often without regard for the revision — so a
/// stale snapshot left by an earlier revision answers for the one that would actually load.
/// This deliberately does not do that. When re-syncing a vendored pipeline, check whether its
/// resolver has drifted from the rules below.
public nonisolated enum HubCache {
    /// The hub cache root: `HF_HUB_CACHE`, else `HF_HOME/hub`, else `~/.cache/huggingface/hub`.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return URL(fileURLWithPath: hubCache)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appending(path: "hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
    }

    /// The cached snapshot directory holding `repoID` at `revision`, or nil when nothing usable
    /// is there.
    ///
    /// The cache records where a branch points in `refs/<revision>`, and that commit is the only
    /// snapshot a load would open: an older one left by a previous revision is still a complete
    /// directory, so answering with it would promise weights that will never be read. When the
    /// refs say nothing about this revision, one snapshot is unambiguous and two are a guess, so
    /// a lone snapshot answers and anything else reads as needing a download.
    ///
    /// A snapshot counts only if it has a config and at least one safetensors file, which is what
    /// tells a finished download apart from an abandoned one.
    public static func snapshot(
        of repoID: String,
        revision: String = "main",
        in cache: URL = directory()
    ) -> URL? {
        let repoDirectory = repoID.replacingOccurrences(of: "/", with: "--")
        let repository = cache.appending(path: "models--\(repoDirectory)")
        let snapshots = repository.appending(path: "snapshots")
        let candidate =
            commit(of: revision, in: repository).map { snapshots.appending(path: $0) }
            ?? onlySnapshot(in: snapshots)
        guard let candidate, isUsable(candidate) else { return nil }
        return candidate
    }

    /// The commit `revision` names: the contents of `refs/<revision>`, or `revision` itself when
    /// it already names a snapshot directory, which is how a revision pinned to a hash arrives.
    private static func commit(of revision: String, in repository: URL) -> String? {
        let reference = repository.appending(path: "refs").appending(path: revision)
        if let contents = try? String(contentsOf: reference, encoding: .utf8) {
            let commit = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !commit.isEmpty { return commit }
        }
        let pinned = repository.appending(path: "snapshots").appending(path: revision)
        return isDirectory(pinned) ? revision : nil
    }

    /// The one snapshot in the cache, when there is exactly one. Several with no ref to choose
    /// between them is ambiguous, and guessing is what this whole lookup exists to avoid.
    private static func onlySnapshot(in snapshots: URL) -> URL? {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: snapshots, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let directories = contents.filter { isDirectory($0) }
        return directories.count == 1 ? directories.first : nil
    }

    private static func isUsable(_ snapshot: URL) -> Bool {
        let files = FileManager.default
        let hasConfig = ["model_index.json", "config.json"].contains {
            files.fileExists(atPath: snapshot.appending(path: $0).path(percentEncoded: false))
        }
        guard hasConfig else { return false }
        let contents = (try? files.contentsOfDirectory(
            at: snapshot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        if contents.contains(where: { $0.pathExtension == "safetensors" }) { return true }
        return contents.contains { entry in
            let nested = (try? files.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil))
            return nested?.contains { $0.pathExtension == "safetensors" } ?? false
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
