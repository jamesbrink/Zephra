import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol
@testable import ZephraLinkHost
@testable import ZephraEngine

@MainActor
@Suite("A multi-host submission is exact, installed-only and idempotent")
struct StrictHostTests {
    @Test("Offers are side effect free and refuse missing or incompatible models")
    func offerAdmission() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        #expect(try await phone.snapshot().multiHost == true)
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "a lighthouse"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 1, settings: settings))
        bed.store.availability[model.id] = .available
        guard case .multiHost(.offer(let offer)) = try await phone.request(.multiHost(.offer(job))) else {
            Issue.record("Missing offer"); await bed.shutdown(); return
        }
        #expect(offer.refusal == nil)
        #expect(bed.store.queue.isEmpty)
        #expect(bed.store.running == nil)
        bed.store.availability[model.id] = nil
        #expect(bed.store.strictRefusal(for: model, settings: settings, count: 1) != nil)
        bed.store.availability[model.id] = .available
        settings.steps = model.capabilities.stepBounds.upperBound + 1
        #expect(bed.store.strictRefusal(for: model, settings: settings, count: 1) != nil)
        await bed.shutdown()
    }

    @Test("Repeated immutable request IDs across sessions return the same batch")
    func duplicateSubmission() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update { $0.stepDelay = .milliseconds(30) }
        await bed.bootstrap()
        let identity = DeviceIdentity()
        let phone = try await bed.pairedPhone(identity: identity)
        _ = try await phone.snapshot()
        let model = bed.store.descriptor
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "a lighthouse"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 2, settings: settings))
        guard case .multiHost(.receipt(let first)) = try await phone.request(.multiHost(.submit(job))) else {
            Issue.record("Missing receipt"); await bed.shutdown(); return
        }
        let another = try await bed.phone(identity: identity)
        _ = try await another.snapshot()
        guard case .multiHost(.receipt(let retry)) = try await another.request(.multiHost(.submit(job))) else {
            Issue.record("Missing retry receipt"); await bed.shutdown(); return
        }
        #expect(first.batchID == retry.batchID)
        #expect(bed.store.queue.count <= 1)
        #expect(bed.store.running?.requiresInstalledModel == true)
        #expect(bed.store.queue.allSatisfy { $0.requiresInstalledModel })
        bed.store.cancel()
        await bed.shutdown()
    }

    @Test("A completed render remains accepted while its output waits to save")
    func savingIsNotInterruption() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        bed.store.saveTask = Task { try? await Task.sleep(for: .milliseconds(500)) }
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let model = bed.store.descriptor
        bed.store.availability[model.id] = .available
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1_000_000_000_000)
        var settings = model.capabilities.clamp(bed.store.settings)
        settings.prompt = "pending write"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 1, settings: settings))
        _ = try await phone.request(.multiHost(.submit(job)))
        try await bed.waitUntil { !bed.store.pendingOutputBatches.isEmpty && bed.store.running == nil }
        bed.host.reconcileReceipts()
        let pending = try bed.host.receipts.read(peer: phone.identity.publicKeys, request: job.request.requestID)
        #expect(pending?.status == .accepted)
        try await bed.waitUntil { bed.store.pendingOutputBatches.isEmpty }
        bed.host.reconcileReceipts()
        #expect(try bed.host.receipts.read(peer: phone.identity.publicKeys, request: job.request.requestID)?.status == .completed)
        await bed.shutdown()
    }

    @Test("Targeted Stop leaves another batch queued and rejects a stale run ID")
    func targetedStop() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(30) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "first"
        store.generate()
        try await bed.waitForStep()
        let first = try #require(store.running)
        var settings = store.settings
        settings.prompt = "other phone"
        let other = try #require(store.enqueue(settings, on: store.descriptor, count: 1))
        store.cancelRun(UUID())
        #expect(store.running?.id == first.id)
        store.cancelRun(first.id)
        #expect(store.queue.map(\.batchID) == [other])
        await store.shutdown()
    }
}
