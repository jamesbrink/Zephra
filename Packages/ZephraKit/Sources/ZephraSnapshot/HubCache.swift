import Foundation

/// Finds what the Hugging Face hub cache already holds, without opening a connection.
///
/// This is what lets a model picker say "13.3 GB download" without starting one, so it reads the
/// disk and nothing else. It is model-agnostic: every answer comes from the repository id and
/// the revision it is given.
///
/// Two layouts live in the one cache directory, and `HubRepository` describes each: the one
/// `hf download` writes and the one the app's own hub client writes. Both are looked at, the
/// `hf` layout first, because a Mac can have either — this one was seeded by `make prefetch`,
/// that one downloaded in the app — and a model downloaded in the app that the next launch did
/// not recognise would be downloaded again.
///
/// A pipeline's own resolver usually performs the same lookup on its way to a download, but as a
/// private step that cannot be asked about, and often without regard for the revision — so a
/// stale snapshot left by an earlier revision answers for the one that would actually load.
/// This deliberately does not do that. When re-syncing a vendored pipeline, check whether its
/// resolver has drifted from `HubRepository`'s rules.
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
    /// is there in either layout.
    public static func snapshot(
        of repoID: String,
        revision: String = "main",
        in cache: URL = directory()
    ) -> URL? {
        for repository in layouts(of: repoID, in: cache) {
            if let snapshot = repository.snapshot(revision: revision) { return snapshot }
        }
        return nil
    }

    /// Every directory in the cache that holds any part of `repoID`, in either layout, whether
    /// or not what is there is complete. This is what a storage listing counts and what a
    /// deletion removes: the whole repository, blobs and bookkeeping included, not one snapshot.
    public static func repositories(of repoID: String, in cache: URL = directory())
        -> [HubRepository]
    {
        layouts(of: repoID, in: cache).filter { isDirectory($0.url) }
    }

    /// Where `repoID` would be in each layout, `hf`'s first, whether or not anything is there.
    private static func layouts(of repoID: String, in cache: URL) -> [HubRepository] {
        let hubDirectory = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
        return [
            HubRepository(
                url: cache.appending(path: hubDirectory, directoryHint: .isDirectory),
                layout: .hub),
            HubRepository(
                url: cache.appending(path: "models", directoryHint: .isDirectory)
                    .appending(path: repoID, directoryHint: .isDirectory),
                layout: .flat),
        ]
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
