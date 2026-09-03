import Foundation

/// The real Qwen-Image snapshot on this machine, when there is one.
///
/// Tests that need published configs or tokenizer files are `.enabled(if:)` this, so a fresh
/// clone with an empty cache reports them skipped rather than quietly green. Point
/// `QWEN_IMAGE_SNAPSHOT` at a directory to use one somewhere else.
enum SnapshotUnderTest {
    /// The repository these tests are written against.
    static let repository = "Qwen/Qwen-Image-2512"

    /// Whether there is one, for `.enabled(if:)`, so a test that needs it is reported as
    /// skipped rather than as a pass that ran nothing.
    static var isPresent: Bool { directory != nil }

    /// The snapshot directory, or nil when the cache has not got it.
    static var directory: URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["QWEN_IMAGE_SNAPSHOT"], !override.isEmpty {
            return URL(filePath: override)
        }
        let snapshots = cacheDirectory(environment)
            .appending(path: "models--\(repository.replacingOccurrences(of: "/", with: "--"))")
            .appending(path: "snapshots")
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: snapshots, includingPropertiesForKeys: nil)) ?? []
        // One snapshot is unambiguous; several without a ref to choose between them is a guess.
        return contents.count == 1 ? contents.first : nil
    }

    private static func cacheDirectory(_ environment: [String: String]) -> URL {
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return URL(filePath: hubCache)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(filePath: home).appending(path: "hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
    }
}
