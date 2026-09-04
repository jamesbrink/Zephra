import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

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

    var last: DownloadProgressEvent? { lock.withLock { events.last } }
}
