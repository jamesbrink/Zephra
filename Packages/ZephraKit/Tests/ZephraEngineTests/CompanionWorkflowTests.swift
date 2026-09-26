import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol
@testable import ZephraEngine

@MainActor @Suite("Companion workflow commands over an authenticated channel")
struct CompanionWorkflowTests {
    @Test func advertisedHistoryAndReorderAreReplaySafe() async throws {
        let bed = CompanionTestBed()
        let a = UUID(), b = UUID()
        let jobs = [a, b].map { QueuedGeneration(model: ModelCatalog.default, settings: .defaults(for: ModelCatalog.default), batchID: $0) }
        bed.store.queue = jobs
        bed.store.promptHistory.record("first", id: a)
        bed.store.promptHistory.record("second", id: b)
        let phone = try await bed.pairedPhone()
        #expect(try await phone.snapshot().workflow == true)
        let history = try await phone.request(.workflow(.history))
        guard case .workflow(.history(let entries)) = history else { Issue.record("Missing history reply"); await bed.shutdown(); return }
        #expect(entries.map(\.prompt) == ["second", "first"])
        let request = Command.workflow(.reorder(id: UUID(), batches: [b, a], entries: jobs.map(\.id)))
        #expect(try await phone.request(request) == .ok)
        #expect(bed.store.queue.map(\.batchID) == [b, a])
        bed.store.queue.append(QueuedGeneration(model: ModelCatalog.default, settings: .defaults(for: ModelCatalog.default)))
        let order = bed.store.queue.map(\.id)
        #expect(try await phone.request(request) == .ok, "lost-reply retry acknowledges the earlier change without moving new jobs")
        #expect(bed.store.queue.map(\.id) == order)
        await bed.shutdown()
    }
    @Test func unknownModelAndUnknownStorageAreRefused() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        guard case .error = try await phone.request(.workflow(.download("does-not-exist"))) else { Issue.record("Unknown model accepted"); await bed.shutdown(); return }
        let operation = Command.workflow(.delete(id: UUID(), token: UUID()))
        let first = try await phone.request(operation)
        #expect(try await phone.request(operation) == first)
        guard case .error(let error) = first else { Issue.record("Unknown token accepted"); await bed.shutdown(); return }
        #expect(error.code == .notFound)
        await bed.shutdown()
    }
}
