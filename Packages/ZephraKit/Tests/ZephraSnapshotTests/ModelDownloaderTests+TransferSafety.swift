import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("a full volume refuses a transfer before any body request")
    func transferSpaceRefusal() async throws {
        let scratch = Scratch("TransferSpace")
        let locations = ModelLocations(root: scratch.url("models"))
        let model = ModelCatalog.zImageTurbo8bit, id = UUID()
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "config.json", "size": 8]])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["config.json": Data(repeating: 7, count: 8)]))
        let pool = ModelTransfers(downloader: ModelDownloader(configuration: StubHub.configuration()),
            capacity: { _ in TransferCapacity(id: "full", available: 0) })
        try await pool.reserve(id, model: model, locations: locations)
        await #expect(throws: BackendError.self) {
            _ = try await TransferAcquisition(id: id, pool: pool).fetch(model, into: locations, release: nil, onProgress: { _ in })
        }
        #expect(StubHub.records.allSatisfy { !$0.path.contains("/resolve/") })
        try await pool.release(id)
    }

    @Test("an explicit revision does not reuse the pin and same-sized bytes of a different revision")
    func explicitRevisionReplacesPartial() async throws {
        let scratch = Scratch("ExplicitRevision")
        let destination = scratch.url("model")
        try scratch.write("old-sha", to: "model/.zephra-revision")
        try scratch.write("main", to: "model/.zephra-requested-revision")
        try scratch.write("old!", to: "model/config.json")
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "config.json", "size": 4]])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["config.json": Data("new!".utf8)], sha: "new-sha"))
        _ = try await ModelDownloader(configuration: StubHub.configuration()).download(
            repoID: "org/model", revision: "v2", patterns: ["*"], into: destination, onProgress: { _ in })
        #expect(try String(contentsOf: destination.appending(path: "config.json"), encoding: .utf8) == "new!")
        #expect(StubHub.records.contains { $0.path.contains("/resolve/new-sha/") })
    }

    @Test("an explicit revision replaces same-sized unmarked legacy bytes", arguments: [false, true])
    func explicitRevisionReplacesLegacy(emptyPin: Bool) async throws {
        let scratch = Scratch("LegacyRevision")
        if emptyPin { try scratch.write("", to: "model/.zephra-revision") }
        try scratch.write("old!", to: "model/config.json")
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "config.json", "size": 4]])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["config.json": Data("new!".utf8)], sha: "new-sha"))
        _ = try await ModelDownloader(configuration: StubHub.configuration()).download(
            repoID: "org/model", revision: "v2", patterns: ["*"], into: scratch.url("model"), onProgress: { _ in })
        #expect(try String(contentsOf: scratch.url("model/config.json"), encoding: .utf8) == "new!")
    }

    @Test("a resume of the same branch keeps its original commit when the branch moves")
    func resumedBranchKeepsPin() async throws {
        let scratch = Scratch("ResumePin")
        try scratch.write("old-sha", to: "model/.zephra-revision")
        try scratch.write("main", to: "model/.zephra-requested-revision")
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "config.json", "size": 4]])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["config.json": Data("same".utf8)], sha: "new-sha"))
        _ = try await ModelDownloader(configuration: StubHub.configuration()).download(
            repoID: "org/model", patterns: ["*"], into: scratch.url("model"), onProgress: { _ in })
        #expect(StubHub.records.allSatisfy { !$0.path.contains("/revision/") })
        #expect(StubHub.records.contains { $0.path.contains("/resolve/old-sha/") })
    }

    @Test("cancellation before headers always settles without a leaked continuation")
    func preCancelledChunkRequest() async throws {
        let session = URLSession(configuration: StubHub.configuration())
        defer { session.invalidateAndCancel() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChunkedDownload().start(URLRequest(url: URL(string: "https://huggingface.co/a")!), on: session)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(task.isCancelled)
    }
}
