import Foundation
import Testing
import ZephraCore
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("two variants share one writer and cancelling one retains the other's source")
    func sharedTransferSurvivesConsumerCancellation() async throws {
        let scratch = Scratch("SharedTransfer")
        let locations = ModelLocations(root: scratch.url("models"))
        let a = ModelCatalog.flux2Klein4bit
        let b = ModelCatalog.flux2Klein8bit
        let pool = ModelTransfers(downloader: ModelDownloader(configuration: StubHub.configuration()))
        let gate = StubBodyGate()
        defer { gate.open() }
        let first = UUID(), second = UUID()
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "model_index.json", "size": 8]])
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["model_index.json": Data(repeating: 7, count: 8)], bodyGate: gate))
        try await pool.reserve(first, model: a, locations: locations)
        try await pool.reserve(second, model: b, locations: locations)
        let one = Task { try await TransferAcquisition(id: first, pool: pool).fetch(a, into: locations, release: nil, onProgress: { _ in }) }
        let two = Task { try await TransferAcquisition(id: second, pool: pool).fetch(b, into: locations, release: nil, onProgress: { _ in }) }
        try await waitForTransfers(1, pool)
        one.cancel()
        try await pool.release(first, discard: true)
        _ = await one.result
        gate.open()
        let path = try await two.value
        #expect(try Data(contentsOf: path.appending(path: "model_index.json")) == Data(repeating: 7, count: 8))
        #expect(StubHub.records.filter { $0.path.contains("/resolve/") }.count == 1)
        #expect(StubHub.records.filter { $0.path.contains("/revision/") }.count == 1)
        try await pool.release(second)
    }

    @Test("the repository lane admits two writers and the third waits for settlement")
    func concurrentTransferLimit() async throws {
        let scratch = Scratch("TransferLimit")
        let locations = ModelLocations(root: scratch.url("models"))
        let models = [ModelCatalog.flux2Klein4bit, ModelCatalog.zImageTurbo4bit, ModelCatalog.zImageTurbo8bit]
        let pool = ModelTransfers(downloader: ModelDownloader(configuration: StubHub.configuration()))
        let listing = try JSONSerialization.data(withJSONObject: [["type": "file", "path": "model_index.json", "size": 8]])
        let gate = StubBodyGate()
        defer { gate.open() }
        StubHub.reset(StubHub.Behaviour(pages: [listing], files: ["model_index.json": Data(repeating: 5, count: 8)], bodyGate: gate))
        let ids = models.map { _ in UUID() }
        var tasks: [Task<URL, any Error>] = []
        for (id, model) in zip(ids, models) {
            try await pool.reserve(id, model: model, locations: locations)
            tasks.append(Task { try await TransferAcquisition(id: id, pool: pool).fetch(model, into: locations, release: nil, onProgress: { _ in }) })
        }
        try await waitForTransfers(2, pool)
        #expect(await pool.active == 2)
        #expect(StubHub.records.filter { $0.path.contains("/resolve/") }.count == 2)
        let started = StubHub.records.first { $0.path.contains("/resolve/") }!
        let activeIndex = try #require(models.firstIndex { started.path.contains("/\($0.sourceName)/resolve/") })
        tasks[activeIndex].cancel()
        try await pool.release(ids[activeIndex])
        try await waitForTransfers(3, pool)
        #expect(await pool.active == 2)
        for (id, task) in zip(ids, tasks) { task.cancel(); try await pool.release(id) }
        for task in tasks { _ = await task.result }
        #expect(await pool.active == 0)
    }

    @Test("a conflicting revision waits until the acquired source's reader releases it")
    func revisionWaitsForReader() async throws {
        let scratch = Scratch("RevisionLease")
        let locations = ModelLocations(root: scratch.url("models"))
        let model = ModelCatalog.flux2Klein4bit
        let pool = ModelTransfers()
        let owner = UUID(), waiter = UUID()
        try await pool.reserve(owner, model: model, locations: locations)
        let claim = try TransferClaim(model, locations)
        let part = try #require(claim.parts.first)
        let changed = ModelDescriptor(
            id: "other", displayName: "Other", variantName: "", backend: model.backend,
            source: .huggingFace(repoID: part.repoID, revision: "different", filePatterns: part.patterns),
            quantization: model.quantization, downloadBytes: model.downloadBytes,
            residentBytes: model.residentBytes, peakBytes: model.peakBytes,
            tiledPeakBytes: model.tiledPeakBytes, maxPromptTokens: model.maxPromptTokens,
            capabilities: model.capabilities)
        let task = Task { try await pool.reserve(waiter, model: changed, locations: locations) }
        for _ in 0..<100 where await pool.waiting.isEmpty { await Task.yield() }
        #expect(await pool.claims[waiter] == nil)
        try await pool.release(owner)
        try await task.value
        #expect(await pool.claims[waiter] != nil)
        try await pool.release(waiter)
    }

    private func waitForTransfers(_ count: Int, _ pool: ModelTransfers) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while StubHub.records.filter({ $0.path.contains("/resolve/") }).count < count {
            guard ContinuousClock.now < deadline else { throw ModelDownloadError.interrupted(reason: "Transfers did not start: \(await pool.testStatus())") }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

extension ModelTransfers {
    func testStatus() -> String {
        "active=\(active), order=\(order.count), " + transfers.values.map {
            "\($0.part.repoID): work=\($0.work?.count ?? -1), owners=\($0.owners.count), result=\(String(describing: $0.result))"
        }.joined(separator: "; ")
    }
}
