import Foundation
import Testing
import ZephraSnapshot
import ZephraTestSupport

@Suite("Hub cache")
struct HubCacheTests {
    /// The repository directory the hub cache would give `acme/weights`.
    private static let repository = "models--acme--weights"

    @Test("the hub cache honours HF_HUB_CACHE first, then HF_HOME")
    func cacheDirectoryFollowsTheEnvironment() {
        #expect(
            HubCache.directory(environment: ["HF_HUB_CACHE": "/cache/hub"]).path
                == "/cache/hub"
        )
        #expect(
            HubCache.directory(environment: ["HF_HOME": "/hf"]).path == "/hf/hub"
        )
        #expect(
            HubCache.directory(
                environment: ["HF_HUB_CACHE": "/cache/hub", "HF_HOME": "/hf"]
            ).path == "/cache/hub"
        )
        #expect(
            HubCache.directory(environment: [:]).path
                .hasSuffix("/.cache/huggingface/hub")
        )
    }

    @Test("a cached snapshot is found only once it has a config and weights")
    func snapshotNeedsConfigAndWeights() throws {
        let scratch = Scratch("HubCache")
        let snapshot = "\(Self.repository)/snapshots/abc123"
        try scratch.make("\(snapshot)/model_index.json")
        #expect(
            Self.lookup(in: scratch) == nil,
            "a config with no weights is an abandoned download, not a model"
        )

        try scratch.make("\(snapshot)/transformer/model.safetensors")
        #expect(Self.lookup(in: scratch) != nil)
    }

    @Test("the revision's refs file picks the snapshot, not whichever is listed first")
    func revisionDecidesWhichSnapshotAnswers() throws {
        let scratch = Scratch("HubCache")
        try scratch.write("fresh\n", to: "\(Self.repository)/refs/main")
        try Self.snapshot("fresh", in: scratch)
        try Self.snapshot("stale", in: scratch)

        #expect(
            Self.lookup(in: scratch)?.lastPathComponent == "fresh",
            "the stale snapshot is complete too, so directory order must not decide"
        )
        #expect(
            Self.lookup(in: scratch, revision: "v2") == nil,
            "no ref for v2 and two snapshots to choose from is a guess, so it needs a download"
        )
    }

    @Test("a revision naming an unfinished snapshot needs a download, stale neighbours aside")
    func revisionPointingAtAnAbandonedDownload() throws {
        let scratch = Scratch("HubCache")
        try scratch.write("half", to: "\(Self.repository)/refs/main")
        try scratch.make("\(Self.repository)/snapshots/half/model_index.json")
        try Self.snapshot("stale", in: scratch)

        #expect(Self.lookup(in: scratch) == nil)
    }

    @Test("with no refs, one snapshot answers and several do not")
    func noRefsFallsBackOnlyWhenUnambiguous() throws {
        let scratch = Scratch("HubCache")
        try Self.snapshot("only", in: scratch)
        #expect(Self.lookup(in: scratch)?.lastPathComponent == "only")

        try Self.snapshot("second", in: scratch)
        #expect(Self.lookup(in: scratch) == nil)
    }

    @Test("a revision pinned to a commit hash resolves without a refs file")
    func revisionGivenAsACommitHash() throws {
        let scratch = Scratch("HubCache")
        try Self.snapshot("abc123", in: scratch)
        try Self.snapshot("def456", in: scratch)

        #expect(Self.lookup(in: scratch, revision: "abc123")?.lastPathComponent == "abc123")
    }

    @Test("a repository the cache has never seen is nothing at all")
    func nothingCachedAtAll() throws {
        let scratch = Scratch("HubCache")
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        #expect(HubCache.snapshot(of: "example/absent", in: scratch.root) == nil)
    }

    /// Lays a complete snapshot down, named after its commit.
    private static func snapshot(_ commit: String, in scratch: Scratch) throws {
        try scratch.make("\(repository)/snapshots/\(commit)/model_index.json")
        try scratch.make("\(repository)/snapshots/\(commit)/transformer/model.safetensors")
    }

    private static func lookup(in scratch: Scratch, revision: String = "main") -> URL? {
        HubCache.snapshot(of: "acme/weights", revision: revision, in: scratch.root)
    }
}
