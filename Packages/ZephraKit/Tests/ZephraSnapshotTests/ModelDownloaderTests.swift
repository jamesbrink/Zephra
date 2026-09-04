import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

@Suite("Downloading a model repository", .serialized)
struct ModelDownloaderTests {
    /// A downloader pointed at the stub instead of the hub.
    private func downloader() -> ModelDownloader {
        ModelDownloader(
            host: URL(string: "https://huggingface.co")!,
            userAgent: "Zephra/test",
            configuration: StubHub.configuration())
    }

    /// A listing page for `files`, in the shape the tree endpoint answers with.
    private func page(_ files: [(String, Int)]) -> Data {
        let entries = files.map { path, size in
            ["type": "file", "path": path, "size": size] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: entries)
    }

    @Test("every listed file lands where the repository names it, and progress ends at one")
    func filesLandFlatWhereTheRepositoryNamesThem() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2), ("vae/model.safetensors", 8)])],
                files: ["model_index.json": Data("{}".utf8), "vae/model.safetensors": Data(repeating: 7, count: 8)]))

        let progress = ProgressLog()
        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"),
            onProgress: { progress.record($0) })

        #expect(scratch.hasFile("models/model_index.json"))
        #expect(try Data(contentsOf: scratch.url("models/vae/model.safetensors")).count == 8)
        #expect(progress.last?.fraction == 1)
        #expect(progress.last?.completedFiles == 2)
        #expect(progress.last?.totalFiles == 2)
    }

    @Test("a body larger than the high-water mark still arrives whole, paused and resumed")
    func aLargeBodyIsPausedAndResumedRatherThanPiledUp() async throws {
        let scratch = Scratch("Download")
        let size = ChunkedDownload.highWater + ChunkedDownload.lowWater
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("big.safetensors", size)])],
                files: ["big.safetensors": Data(repeating: 9, count: size)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(try Data(contentsOf: scratch.url("models/big.safetensors")).count == size)
    }

    @Test("a release and the adapter merged into it are one download, and one bar")
    func aModelWithAnAdapterFetchesBothAsOne() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2), ("lightning.safetensors", 8)])],
                files: [
                    "model_index.json": Data("{}".utf8),
                    "lightning.safetensors": Data(repeating: 3, count: 8),
                ]))

        let progress = ProgressLog()
        let locations = ModelLocations(root: scratch.url("models"))
        let release = try await downloader().fetch(
            Self.withAdapter(), into: locations, onProgress: { progress.record($0) })

        #expect(release == locations.downloads(repoID: "org/repo"))
        #expect(scratch.hasFile("models/Downloads/org--repo/model_index.json"))
        #expect(scratch.hasFile("models/Downloads/org--lora/lightning.safetensors"))
        #expect(
            progress.first?.totalFiles == 2,
            "both repositories are listed before a byte moves, so the bar knows its length")
        #expect(progress.last?.fraction == 1)
        #expect(progress.last?.completedFiles == 2)
    }

    @Test("a release already on this Mac is kept, and only the missing adapter is fetched")
    func anExistingReleaseFetchesOnlyItsAdapter() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("lightning.safetensors", 8)])],
                files: ["lightning.safetensors": Data(repeating: 3, count: 8)]))

        let locations = ModelLocations(root: scratch.url("models"))
        let cached = scratch.url("cache/models--org--repo/snapshots/abc")
        try scratch.make("cache/models--org--repo/snapshots/abc/model_index.json")
        let release = try await downloader().fetch(
            Self.withAdapter(), into: locations, release: cached, onProgress: { _ in })

        #expect(release == cached)
        #expect(scratch.hasFile("models/Downloads/org--lora/lightning.safetensors"))
        #expect(
            !scratch.hasFile("models/Downloads/org--repo/model_index.json"),
            "nothing of the release moved; the one page the stub served was the adapter's")
    }

    @Test("an adapter repository that is not there stops the download before the release moves")
    func aMissingAdapterFailsBeforeAnythingIsFetched() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(StubHub.Behaviour(pages: [page([("model_index.json", 2)])], files: [:]))

        await #expect(throws: (any Error).self) {
            _ = try await downloader().fetch(
                Self.withAdapter(), into: ModelLocations(root: scratch.url("models")),
                onProgress: { _ in })
        }
        #expect(
            !scratch.hasFile("models/Downloads/org--repo/model_index.json"),
            "nothing in the adapter's repository matches, so the release is never started")
    }

    /// A model whose release is one repository and whose distillation is another.
    private static func withAdapter() -> ModelDescriptor {
        let base = ModelCatalog.default
        return ModelDescriptor(
            id: "adapter-test", displayName: base.displayName, variantName: base.variantName,
            backend: base.backend,
            source: .huggingFace(
                repoID: "org/repo", revision: "main", filePatterns: ["model_index.json"]),
            quantization: base.quantization, downloadBytes: 2,
            residentBytes: base.residentBytes, peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes, maxPromptTokens: base.maxPromptTokens,
            capabilities: base.capabilities, builtBytes: 4,
            adapters: [
                ModelAdapter(repoID: "org/lora", file: "lightning.safetensors", bytes: 8)
            ])
    }

    @Test("a repository listed over two pages is fetched whole")
    func pagesAreFollowed() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("a.json", 1)]), page([("b.json", 1)])],
                files: ["a.json": Data("1".utf8), "b.json": Data("2".utf8)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(scratch.hasFile("models/a.json"))
        #expect(scratch.hasFile("models/b.json"))
    }

    @Test("only the files the patterns name are fetched")
    func patternsDecideWhatIsFetched() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2), ("assets/sample.png", 4)])],
                files: ["model_index.json": Data("{}".utf8), "assets/sample.png": Data(repeating: 1, count: 4)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*.json"], into: scratch.url("models"),
            onProgress: { _ in })

        #expect(scratch.hasFile("models/model_index.json"))
        #expect(!scratch.hasFile("models/assets/sample.png"))
        #expect(StubHub.records.filter { $0.path.contains("/resolve/") }.count == 1)
    }

    @Test("a part-transferred file asks for the rest and appends it")
    func aPartialFileResumes() async throws {
        let scratch = Scratch("Download")
        let whole = Data("0123456789".utf8)
        try scratch.write("01234", to: "models/big.bin.incomplete")
        StubHub.reset(
            StubHub.Behaviour(pages: [page([("big.bin", 10)])], files: ["big.bin": whole]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(try Data(contentsOf: scratch.url("models/big.bin")) == whole)
        #expect(!scratch.hasFile("models/big.bin.incomplete"))
        let fetch = try #require(StubHub.records.first { $0.path.contains("/resolve/") })
        #expect(fetch.range == "bytes=5-")
    }

    @Test("a resume names the file it started, and a file that changed comes back whole")
    func aChangedFileIsNotSplicedOnto() async throws {
        let scratch = Scratch("Download")
        let whole = Data("0123456789".utf8)
        try scratch.write("XXXXX", to: "models/big.bin.incomplete")
        try scratch.write("v1", to: "models/big.bin.incomplete.etag")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("big.bin", 10)])], files: ["big.bin": whole], etag: "v2"))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        let fetch = try #require(StubHub.records.last)
        #expect(fetch.range == "bytes=5-")
        #expect(fetch.ifRange == "v1", "the resume asks for the representation it started")
        #expect(try Data(contentsOf: scratch.url("models/big.bin")) == whole)
        #expect(!scratch.hasFile("models/big.bin.incomplete.etag"), "gone with the partial")
    }

    @Test("a download is pinned to one commit, and a resumed one keeps the commit it started at")
    func aTransferIsPinnedToACommit() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2)])], files: ["model_index.json": Data("{}".utf8)],
                sha: "second"))
        try scratch.write("first", to: "models/.zephra-revision")

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        let paths = StubHub.records.map(\.path)
        #expect(paths.contains("/api/models/org/repo/tree/first"), "listed at the pinned commit")
        #expect(paths.contains("/org/repo/resolve/first/model_index.json"), "fetched at it too")
        #expect(!paths.contains { $0.contains("/revision/") }, "the branch was not asked again")
        #expect(!scratch.hasFile("models/.zephra-revision"), "the pin goes with the last file")

        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 3)])], files: ["model_index.json": Data("{ }".utf8)],
                sha: "third"))
        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })
        #expect(
            StubHub.records.map(\.path).contains("/org/repo/resolve/third/model_index.json"),
            "a fresh transfer asks the branch and pins what it answers")
    }

    @Test("a path that would leave the folder is refused before anything is written")
    func aTraversingPathIsRefused() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("../escape.json", 2)])], files: ["../escape.json": Data("{}".utf8)]))

        await #expect(throws: (any Error).self) {
            _ = try await downloader().download(
                repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })
        }
        #expect(!scratch.hasFile("escape.json"))
    }

    @Test("a folder two parts share is not recorded finished until the second part is")
    func aSharedFolderFinishesWithItsLastPart() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("a.safetensors", 2), ("b.safetensors", 2)])],
                files: ["a.safetensors": Data("aa".utf8)]))
        let folder = scratch.url("models")
        let parts = ["a.safetensors", "b.safetensors"].map {
            RepositoryDownload(repoID: "org/lora", revision: "main", patterns: [$0], destination: folder)
        }

        await #expect(throws: (any Error).self) {
            try await downloader().download(parts, onProgress: { _ in })
        }
        #expect(scratch.hasFile("models/a.safetensors"), "the first part did land")
        #expect(!scratch.hasFile("models/.zephra-commit"), "the folder is not finished")
        #expect(scratch.hasFile("models/.zephra-revision"), "and is still pinned for the retry")
    }

    @Test("a partial an interrupted `hf download` left in the folder goes once the transfer is whole")
    func hubPartialsAreDroppedOnCompletion() async throws {
        let scratch = Scratch("Download")
        try scratch.make("models/.cache/huggingface/download/assets/big.png.incomplete")
        try scratch.make("models/.cache/huggingface/download/model_index.json.metadata")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 3)])], files: ["model_index.json": Data("{ }".utf8)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(!scratch.hasFile("models/.cache/huggingface/download/assets/big.png.incomplete"))
        #expect(scratch.hasFile("models/.cache/huggingface/download/model_index.json.metadata"))
        #expect(HubSnapshotCheck.incompleteFiles(in: scratch.url("models")).isEmpty)
    }

    @Test("a folder component that is already a link out of the folder is refused too")
    func aLinkedComponentIsRefused() async throws {
        let scratch = Scratch("Download")
        try scratch.make("elsewhere", isDirectory: true)
        _ = try scratch.link("models/vae", to: scratch.url("elsewhere").path(percentEncoded: false))
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("vae/config.json", 2)])], files: ["vae/config.json": Data("{}".utf8)]))

        await #expect(throws: (any Error).self) {
            _ = try await downloader().download(
                repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })
        }
        #expect(!scratch.hasFile("elsewhere/config.json"))
    }

    @Test("a file left by an earlier commit is not taken for part of a newer one")
    func anEarlierCommitsFilesAreNotReused() async throws {
        let scratch = Scratch("Download")
        try scratch.write("{}", to: "models/model_index.json")
        try scratch.write("old", to: "models/.zephra-commit")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2)])], files: ["model_index.json": Data("[]".utf8)],
                sha: "new"))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(
            try String(contentsOf: scratch.url("models/model_index.json"), encoding: .utf8) == "[]",
            "same size, other commit: fetched again rather than kept")
        #expect(try String(contentsOf: scratch.url("models/.zephra-commit"), encoding: .utf8) == "new")
    }

    @Test("a server that ignores the range is not spliced onto: the file starts over")
    func anIgnoredRangeStartsOver() async throws {
        let scratch = Scratch("Download")
        let whole = Data("0123456789".utf8)
        try scratch.write("01234", to: "models/big.bin.incomplete")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("big.bin", 10)])], files: ["big.bin": whole], ignoresRange: true))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(try Data(contentsOf: scratch.url("models/big.bin")) == whole)
    }

    @Test("a file that ends early is not renamed, and its bytes are kept for the next try")
    func aTruncatedFileIsNotTrusted() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("big.bin", 10)])],
                files: ["big.bin": Data("0123456789".utf8)], truncatesTo: 4))

        await #expect(throws: (any Error).self) {
            _ = try await downloader().download(
                repoID: "org/repo", patterns: ["*"], into: scratch.url("models"),
                onProgress: { _ in })
        }
        #expect(!scratch.hasFile("models/big.bin"))
        #expect(scratch.hasFile("models/big.bin.incomplete"))
        #expect(!HubSnapshotCheck.isComplete(scratch.url("models")))
    }

    @Test("a file already in place at the listed size is not fetched again")
    func afinishedFileIsLeftAlone() async throws {
        let scratch = Scratch("Download")
        try scratch.write("{}", to: "models/model_index.json")
        StubHub.reset(
            StubHub.Behaviour(
                pages: [page([("model_index.json", 2)])], files: ["model_index.json": Data("{}".utf8)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(StubHub.records.filter { $0.path.contains("/resolve/") }.isEmpty)
    }

    @Test("stopping keeps the bytes already on disk, and trying again picks them up")
    func stoppingLeavesTheBytesToResumeFrom() async throws {
        let scratch = Scratch("Download")
        let whole = Data("0123456789".utf8)
        try scratch.write("01234", to: "models/big.bin.incomplete")
        let listing = page([("big.bin", 10)])
        StubHub.reset(
            StubHub.Behaviour(pages: [listing], files: ["big.bin": whole], pause: 1))

        let downloader = downloader()
        let destination = scratch.url("models")
        let stopped = Task {
            try await downloader.download(
                repoID: "org/repo", patterns: ["*"], into: destination, onProgress: { _ in })
        }
        try await Task.sleep(for: .milliseconds(100))
        stopped.cancel()
        await #expect(throws: CancellationError.self) { try await stopped.value }
        #expect(!scratch.hasFile("models/big.bin"), "nothing half-finished is put in place")
        #expect(try Data(contentsOf: scratch.url("models/big.bin.incomplete")).count == 5)

        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["big.bin": whole]))
        _ = try await downloader.download(
            repoID: "org/repo", patterns: ["*"], into: destination, onProgress: { _ in })
        #expect(try Data(contentsOf: scratch.url("models/big.bin")) == whole)
        #expect(StubHub.records.contains { $0.range == "bytes=5-" }, "it carried on from five")
    }

    @Test("no Authorization header is sent, even with a token in the environment")
    func noTokenIsEverSent() async throws {
        let scratch = Scratch("Download")
        setenv("HF_TOKEN", "hf_a_stale_token", 1)
        defer { unsetenv("HF_TOKEN") }
        StubHub.reset(
            StubHub.Behaviour(pages: [page([("a.json", 1)])], files: ["a.json": Data("1".utf8)]))

        _ = try await downloader().download(
            repoID: "org/repo", patterns: ["*"], into: scratch.url("models"), onProgress: { _ in })

        #expect(StubHub.records.allSatisfy { $0.authorization == nil })
        #expect(!StubHub.records.isEmpty)
    }

    @Test("a repository that is not there is a permanent answer, not a transfer to retry")
    func aMissingRepositoryIsPermanent() async throws {
        let scratch = Scratch("Download")
        StubHub.reset(StubHub.Behaviour(listingStatus: 404))

        await #expect(throws: ModelDownloadError.repositoryNotFound(repoID: "org/repo")) {
            _ = try await downloader().download(
                repoID: "org/repo", patterns: ["*"], into: scratch.url("models"),
                onProgress: { _ in })
        }
        #expect(ModelDownloadError.repositoryNotFound(repoID: "org/repo").isPermanent)
        #expect(!ModelDownloadError.interrupted(reason: "the line dropped").isPermanent)
    }
}

/// The progress events one download reported, so a test can look at the last one.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DownloadProgressEvent] = []

    func record(_ event: DownloadProgressEvent) {
        lock.withLock { events.append(event) }
    }

    var first: DownloadProgressEvent? { lock.withLock { events.first } }

    var last: DownloadProgressEvent? { lock.withLock { events.last } }
}
