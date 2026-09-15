import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol
@testable import ZephraLinkHost
@testable import ZephraEngine

@MainActor @Suite("Receipt disk failures across the host command boundary")
struct ReceiptFaultBoundaryTests {
    @Test("A failed write never duplicates possible work", arguments: [0, 1, 2, 3])
    func boundaries(_ boundary: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var writes = 0
        let receipts = GenerationReceipts(root: root) { data, url in
            writes += 1
            let target = boundary < 2 ? 1 : 2
            if writes == target && boundary % 2 == 0 { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
            if writes == target && boundary % 2 == 1 { throw CocoaError(.fileWriteUnknown) }
        }
        let bed = CompanionTestBed(receipts: receipts)
        await bed.bootstrap()
        let identity = DeviceIdentity()
        let phone = try await bed.pairedPhone(identity: identity)
        _ = try await phone.snapshot()
        let model = bed.store.descriptor
        bed.store.availability[model.id] = .available
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "write boundary"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 1, settings: settings))
        let reply = try await phone.request(.multiHost(.submit(job)))
        if boundary < 2 {
            #expect(bed.store.running == nil && bed.store.queue.isEmpty && bed.store.history.isEmpty)
            if case .error = reply {} else { Issue.record("A pre-enqueue write failed without an error") }
        } else {
            guard case .multiHost(.receipt(let receipt)) = reply else {
                Issue.record("Possible acceptance was reported as definite rejection"); await bed.shutdown(); return
            }
            #expect(receipt.status == .prepared)
            let duplicate = try await phone.request(.multiHost(.submit(job)))
            guard case .multiHost(.receipt(let repeated)) = duplicate else {
                Issue.record("Missing retained receipt"); await bed.shutdown(); return
            }
            #expect(repeated.batchID == receipt.batchID)
            #expect(bed.store.history.count + bed.store.queue.count + (bed.store.running == nil ? 0 : 1) == 1)
        }
        await bed.shutdown()
        let reopened = GenerationReceipts(root: root)
        let held = try reopened.read(peer: identity.publicKeys, request: job.request.requestID)
        if boundary == 0 { #expect(held == nil) }
        else if boundary >= 2, let held, held.status == .completed {
            // Generation may finish while the duplicate request or shutdown awaits.
            // Reconciliation may then persist completion after the injected write failure.
            let batch = try #require(held.batchID)
            #expect(bed.store.savedBatchCounts[batch] == 1)
        }
        else { #expect(held?.status == (boundary == 3 ? .unknown : .prepared)) }
        // Replay through a fresh host command handler. A durable ambiguous receipt wins over enqueue.
        if boundary > 0 {
            let restarted = CompanionTestBed(receipts: reopened)
            await restarted.bootstrap()
            let again = try await restarted.pairedPhone(identity: identity)
            _ = try await again.snapshot()
            guard case .multiHost(.receipt(let recovered)) = try await again.request(.multiHost(.submit(job))) else {
                Issue.record("Restart lost an ambiguous receipt"); await restarted.shutdown(); return
            }
            #expect(recovered.batchID == held?.batchID)
            #expect(restarted.store.running == nil && restarted.store.queue.isEmpty && restarted.store.history.isEmpty)
            await restarted.shutdown()
        }
    }
}
