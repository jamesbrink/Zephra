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
        try await bed.waitForStep()
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
        try await bed.waitForStep()
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
        try await bed.waitForStep()
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

    @Test("generate does nothing without a prompt, or while the model is still being read in")
    func queueGuards() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(500) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        // Nothing loaded is no longer a reason to refuse: the queue loads what an entry needs.
        // An empty prompt still is, whatever the engine is doing.
        store.settings.prompt = "   "
        #expect(!store.canQueue)

        let bootstrap = Task { await store.bootstrap() }
        try await bed.waitFor(store, toReach: .loading(.preparing))
        store.settings.prompt = "too early"
        #expect(!store.canQueue, "a load in flight is not a queue to join")
        store.generate()
        #expect(store.queue.isEmpty)

        bed.control.update { $0.loadDelay = .zero }
        await bootstrap.value
        await store.settle()
        store.settings.prompt = "   "
        #expect(!store.canQueue)
        await store.shutdown()
    }

    @Test("a memory refusal drops its own batch and leaves the others waiting")
    func aRefusalKeepsTheOtherBatches() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()
        // Two presses queued behind the one being rendered, and a machine that runs out
        // before the first of them comes round.
        store.generate()
        store.generate()
        let survivor = try #require(store.queue.last?.batchID)
        #expect(store.queue.count == 2)
        bed.machineMemory = MemoryGuardStoreTests.starved()

        try await bed.waitUntil { if case .failed = store.state { return true }; return false }
        guard case .failed(let error) = store.state,
            case .insufficientMemory(let shortfall) = error
        else {
            Issue.record("expected a memory refusal, got \(store.state)")
            await store.shutdown()
            return
        }
        #expect(shortfall.phase == .run)
        #expect(store.queue.count == 1, "only the refused batch is put down")
        #expect(store.queue.first?.batchID == survivor, "the one behind it keeps its place")
        #expect(store.history.count == 1, "the run that was already going still landed")

        // The next press is what drains the survivor: a `.failed` is a sentence to read, and
        // draining on would have replaced it before anybody had.
        bed.machineMemory = MachineMemory(
            physicalBytes: 128_000_000_000, availableBytes: 120_000_000_000)
        store.generate()
        try await bed.waitUntil { store.history.count == 3 }
        await store.settle()
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("a refused batch takes every seed's chain with it, and nobody else's")
    func arefusedBatchDropsEveryChain() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        // Four seeds of one press of a chained clip. `generate(count:)` plans a chain per
        // seed, so there are four to put down and only one of them is the job that was
        // refused; a `ChainProgress` left behind holds PNG frames nothing will read again.
        let batch = UUID()
        var seeds: [QueuedGeneration] = []
        for index in 0..<4 {
            let chain = UUID()
            store.chains[chain] = ChainProgress(segments: [9, 9], source: nil)
            seeds.append(
                QueuedGeneration(
                    model: store.descriptor, settings: store.settings, batchID: batch,
                    batchIndex: index,
                    chain: ChainSegment(chainID: chain, index: 0, count: 2)))
        }
        // Another press, on a chain of its own, which the refusal must leave alone.
        let survivingChain = UUID()
        store.chains[survivingChain] = ChainProgress(segments: [9, 9], source: nil)
        let survivor = QueuedGeneration(
            model: store.descriptor, settings: store.settings,
            chain: ChainSegment(chainID: survivingChain, index: 0, count: 2))
        store.queue = Array(seeds.dropFirst()) + [survivor]
        store.running = seeds[0]
        #expect(store.chains.count == 5)

        store.failJob(seeds[0], with: .backend(.generationFailed("no room")))

        #expect(store.queue.map(\.id) == [survivor.id], "only the refused batch leaves the queue")
        #expect(Array(store.chains.keys) == [survivingChain], "and every seed's chain with it")
        #expect(store.running == nil)
        await store.shutdown()
    }
}
