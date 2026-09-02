import Foundation

/// Finds what the Hugging Face hub cache already holds, without opening a connection.
///
/// The vendored `ModelResolution` does the same lookup on its way to a download, but only as a
/// private step it cannot be asked about. This mirrors its two rules exactly — the same cache
/// directory, honouring `HF_HUB_CACHE` then `HF_HOME`, and the same test for a usable snapshot —
/// so an answer here matches what a load would find. Keep the two in step when re-syncing the
/// vendored copy.
nonisolated enum ZImageHubCache {
    /// The hub cache root: `HF_HUB_CACHE`, else `HF_HOME/hub`, else `~/.cache/huggingface/hub`.
    static func directory(
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

    /// The cached snapshot directory holding `repoID`'s weights, or nil when nothing usable is
    /// there. A snapshot counts only if it has a config and at least one safetensors file, which
    /// is what tells a finished download apart from an abandoned one.
    static func snapshot(of repoID: String, in cache: URL = directory()) -> URL? {
        let files = FileManager.default
        let repoDirectory = repoID.replacingOccurrences(of: "/", with: "--")
        let snapshots = cache.appending(path: "models--\(repoDirectory)").appending(path: "snapshots")
        guard let candidates = try? files.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return candidates.first { isUsable($0) }
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
}
