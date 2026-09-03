import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore batches")
struct GenerationBatchTests {
    @Test("four seeds of one prompt run one after another and share a batch")
    func fourSeedsRunDown() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(5) }

        store.settings.prompt = "a red bicycle against a limestone wall"
        store.settings.steps = 4
        let seed = store.settings.seed
        store.generate(count: 4)

        while store.isRunning || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.count == 4)
        #expect(Set(store.history.compactMap(\.batchID)).count == 1)
        #expect(Set(store.history.map(\.settings.seed)).count == 4)
        #expect(store.history.contains { $0.settings.seed == seed })
        #expect(store.currentBatch.count == 4)
        #expect(store.pendingInCurrentBatch == 0)
        #expect(store.running == nil)
    }

    @Test("the running seed is observable and is not also sitting in the queue")
    func runningIsNotQueued() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "a red bicycle against a limestone wall"
        store.settings.steps = 8
        store.generate(count: 3)
        try await bed.waitForFirstStep()

        let running = try #require(store.running)
        #expect(store.queue.count == 2)
        #expect(!store.queue.contains { $0.id == running.id })
        #expect(store.queue.allSatisfy { $0.batchID == running.batchID })
        #expect(store.pendingInCurrentBatch == 3)
        #expect(running.batchIndex == 0)

        store.cancel()
        await store.settle()
    }

    @Test("clearing the queue drops what is waiting and leaves the running seed alone")
    func clearingLeavesTheRunningSeed() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(20) }

        store.settings.prompt = "a red bicycle against a limestone wall"
        store.settings.steps = 6
        store.generate(count: 4)
        try await bed.waitForFirstStep()
        store.clearQueue()

        #expect(store.queue.isEmpty)
        #expect(store.running != nil)
        #expect(store.pendingInCurrentBatch == 1)

        while store.isRunning { await store.settle() }
        await store.settle()
        #expect(store.history.count == 1, "only the seed that was already running produces an image")
        #expect(store.state == .ready)
    }

    @Test("stopping mid-batch drops the seeds that had not started")
    func stoppingDropsThePendingSeeds() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "a red bicycle against a limestone wall"
        store.settings.steps = 8
        store.generate(count: 4)
        try await bed.waitForFirstStep()
        store.cancel()

        #expect(store.queue.isEmpty)
        #expect(store.running == nil)
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.history.isEmpty)
        #expect(store.currentBatch.isEmpty)
        #expect(store.pendingInCurrentBatch == 0)
    }

    @Test("a batch is never larger than the limit, and never smaller than one")
    func countIsClamped() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "a red bicycle against a limestone wall"
        store.settings.steps = 8
        store.generate(count: 99)
        try await bed.waitForFirstStep()
        #expect(store.queue.count == GenerationStore.batchLimit - 1)
        store.cancel()
        await store.settle()

        store.generate(count: 0)
        try await bed.waitForFirstStep()
        #expect(store.running != nil)
        #expect(store.queue.isEmpty)
        store.cancel()
        await store.settle()
    }
}
