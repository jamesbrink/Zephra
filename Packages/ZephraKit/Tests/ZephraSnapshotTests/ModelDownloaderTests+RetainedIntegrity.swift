import Foundation
import Testing
import ZephraCore
import ZephraTestSupport
@testable import ZephraSnapshot

extension ModelDownloaderTests {
    @Test("A resumed mirror repairs equal-size corruption before admission", arguments: [false, true])
    func retainedMirrorIntegrity(corrupt: Bool) async throws {
        let fixture = MirrorFixture.self
        let scratch = Scratch("RetainedMirror")
        let locations = ModelLocations(root: scratch.url("models"))
        let partial = ModelDownloader.prebuiltPartial(of: fixture.model, in: locations)
        for (name, bytes) in fixture.files {
            let url = partial.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        let weight = partial.appending(path: "transformer/model.safetensors")
        if corrupt { try Data(repeating: 8, count: 24).write(to: weight) }
        StubHub.reset(StubHub.Behaviour(files: fixture.served(), index: fixture.index()))
        let pool = ModelTransfers(downloader: downloader(), capacity: { _ in
            TransferCapacity(id: "fixture", available: (256 << 20) + 24)
        })
        let id = UUID()
        try await pool.reserve(id, model: fixture.model, locations: locations)
        let result = try await TransferAcquisition(id: id, pool: pool)
            .fetchPrebuilt(fixture.model, into: locations) { _ in }
        try await pool.release(id)
        let built = try #require(result)
        #expect(try Data(contentsOf: built.appending(path: "transformer/model.safetensors")) == fixture.files["transformer/model.safetensors"])
        #expect(StubHub.records.filter { $0.path.hasSuffix("model.safetensors") }.count == (corrupt ? 1 : 0))
    }

    @Test("Corrupt retained files are not credited against a full volume")
    func corruptFinalNeedsAdmission() async throws {
        let fixture = MirrorFixture.self
        let scratch = Scratch("CorruptAdmission")
        let locations = ModelLocations(root: scratch.url("models"))
        let partial = ModelDownloader.prebuiltPartial(of: fixture.model, in: locations)
        for (name, bytes) in fixture.files {
            let url = partial.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        try Data(repeating: 8, count: 24).write(to: partial.appending(path: "transformer/model.safetensors"))
        StubHub.reset(StubHub.Behaviour(files: fixture.served(), index: fixture.index()))
        let pool = ModelTransfers(downloader: downloader(), capacity: { _ in TransferCapacity(id: "full", available: 256 << 20) })
        let id = UUID()
        try await pool.reserve(id, model: fixture.model, locations: locations)
        #expect(try await TransferAcquisition(id: id, pool: pool).fetchPrebuilt(fixture.model, into: locations) { _ in } == nil)
        try await pool.release(id)
        #expect(StubHub.records.filter { $0.path.hasSuffix("model.safetensors") }.isEmpty)
    }

    @Test("Cancellation during retained-file validation preserves bytes")
    func cancelledIntegrity() async throws {
        let scratch = Scratch("CancelledIntegrity")
        let url = try scratch.make("weight")
        try Data(repeating: 1, count: 16).write(to: url)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FileDigest.sha256(of: url)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(scratch.hasFile("weight"))
    }
}
