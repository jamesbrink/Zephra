import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore queue")
struct GenerationQueueTests {
    @Test("prompts fired while a generation runs queue up and run one after another")
    func queueRunsDown() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(15) }

        store.settings.prompt = "first"
        store.settings.steps = 4
        store.generate()
        try await bed.waitForFirstStep()
        #expect(!store.canGenerate)
        #expect(store.canQueue)

        store.settings.prompt = "second"
        store.generate()
        store.settings.prompt = "third"
        store.generate()
        #expect(store.queue.count == 2)
        #expect(store.queue.map(\.settings.prompt) == ["second", "third"])

        while store.isRunning || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.queue.isEmpty)
        #expect(store.history.map(\.settings.prompt) == ["third", "second", "first"])
    }

    @Test("a queued prompt can be taken back out, and stop drops the whole queue")
    func removeAndCancel() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "running"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForFirstStep()
        store.settings.prompt = "keep"
        store.generate()
        store.settings.prompt = "drop"
        store.generate()
        let dropped = store.queue.last!
        store.removeFromQueue(dropped.id)
        #expect(store.queue.map(\.settings.prompt) == ["keep"])

        store.cancel()
        #expect(store.queue.isEmpty)
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.history.isEmpty)
    }

    @Test("picking an earlier image to vary leaves the queue alone")
    func selectKeepsTheQueue() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "running"
        store.settings.steps = 6
        store.generate()
        try await bed.waitForFirstStep()
        store.settings.prompt = "waiting"
        store.generate()
        #expect(store.queue.count == 1)

        var earlier = GenerationSettings.defaults(for: ModelCatalog.default)
        earlier.prompt = "a harbour in the rain"
        store.select(
            GeneratedImage(
                pngData: MockBackend.pngData,
                settings: earlier,
                modelID: ModelCatalog.default.id,
                duration: .seconds(2)
            )
        )

        #expect(store.queue.map(\.settings.prompt) == ["waiting"], "select must not touch the queue")
        while store.isRunning || !store.queue.isEmpty { await store.settle() }
        await store.settle()
        #expect(store.history.map(\.settings.prompt) == ["waiting", "running"])
    }

    @Test("generate does nothing without a prompt or while the model is still loading")
    func queueGuards() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.settings.prompt = "too early"
        #expect(!store.canQueue)
        store.generate()
        #expect(store.queue.isEmpty)
        await store.bootstrap()
        store.settings.prompt = "   "
        #expect(!store.canQueue)
    }
}
