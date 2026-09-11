import Foundation
import ZephraCore

/// A real model snapshot on this Mac, when there is one, for the tests that read published
/// configs, tokenizer files or safetensors headers.
///
/// Those tests are `.enabled(if:)` this, so a fresh clone with nothing on the disk reports them
/// skipped rather than quietly green. The places looked in, in order: the environment variable,
/// which names a directory outright; the app's own models folder, where a variant packed on this
/// Mac (`<models>/<descriptor id>`) carries the release's configs and tokenizer, and the download
/// (`<models>/Downloads/<org>--<repo>`) is the release itself; then the Hugging Face cache, when
/// it holds exactly one snapshot of the repository. `release` skips the packed variants, for a
/// test that reads the release's own shard headers.
public struct SnapshotUnderTest: Sendable {
    /// The repository the tests are written against.
    public let repository: String
    /// The environment variable that names a snapshot directory outright.
    public let environmentVariable: String

    public init(repository: String, environmentVariable: String) {
        self.repository = repository
        self.environmentVariable = environmentVariable
    }

    /// Whether any snapshot is here, for `.enabled(if:)`.
    public var isPresent: Bool { directory != nil }

    /// Whether the release itself is here, for a test that reads its shard headers.
    public var hasRelease: Bool { release != nil }

    /// The release, or a variant packed from it: whichever is found first.
    public var directory: URL? {
        override ?? (builtVariants + [download] + cached).first(where: exists)
    }

    /// The release itself, never a packed variant.
    public var release: URL? {
        override ?? ([download] + cached).first(where: exists)
    }

    // The override is taken as given, so a wrong path fails the test that reads it rather than
    // skipping it: a typo in the variable should not look like a Mac with nothing on it.

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    private var override: URL? {
        guard let path = environment[environmentVariable], !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    /// Every catalog variant packed from this repository, where the app would have built it.
    private var builtVariants: [URL] {
        ModelCatalog.all
            .filter { $0.sourceName == repository && $0.isBuiltLocally }
            .map { ModelLocations.default.built($0) }
    }

    private var download: URL {
        ModelLocations.default.downloads(repoID: repository)
    }

    /// The hub cache's snapshot, when it holds exactly one: several without a ref to choose
    /// between them is a guess.
    private var cached: [URL] {
        let snapshots =
            hubCache
            .appending(path: "models--\(repository.replacingOccurrences(of: "/", with: "--"))")
            .appending(path: "snapshots")
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: snapshots, includingPropertiesForKeys: nil)) ?? []
        return contents.count == 1 ? contents : []
    }

    private var hubCache: URL {
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return URL(filePath: hubCache)
        }
        if let home = environment["HF_HOME"], !home.isEmpty {
            return URL(filePath: home).appending(path: "hub")
        }
        // `homeDirectoryForCurrentUser` is a Mac API and this module is linked by the
        // companion's suites too, which run on a simulator with no hub cache to find. The
        // container's home is answer enough there; the Mac keeps the one it has always had.
        #if os(macOS)
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".cache/huggingface/hub")
        #else
            return URL(filePath: NSHomeDirectory()).appending(path: ".cache/huggingface/hub")
        #endif
    }

    private func exists(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
