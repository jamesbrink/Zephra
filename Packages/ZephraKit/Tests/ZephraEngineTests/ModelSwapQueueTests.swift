import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Model switching while the engine is busy: the choice lands at once, the running image keeps
/// its model, queued entries keep theirs, and the swap happens between them.
@MainActor
@Suite("GenerationStore model swaps with a queue")
struct ModelSwapQueueTests {
    @Test("switching mid-run finishes the running image on its model and swaps for the queue")
    func switchWhileRunningQueuesTheSwap() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "first"
        store.generate()
        try await bed.waitForFirstStep()

        store.switchModel(to: ModelSwitchingTests.smaller)
        #expect(store.descriptor.id == ModelSwitchingTests.smaller.id, "the choice lands at once")
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "the run keeps its model")
        #expect(store.state.isBusy)
        store.settings.prompt = "second"
        store.generate()
        #expect(store.queue.first?.model.id == ModelSwitchingTests.smaller.id)

        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["second", "first"])
        #expect(store.history.map(\.modelID) == [ModelSwitchingTests.smaller.id, ModelCatalog.default.id])
        #expect(bed.control.settings.unloads == 1)
        #expect(bed.control.settings.loads == 2)
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.smaller.id)
        #expect(store.state == .ready)
    }

    @Test("a switch with an empty queue after a run lands as soon as the run ends")
    func switchLandsAfterTheRun() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "only"
        store.generate()
        try await bed.waitForFirstStep()

        store.switchModel(to: ModelSwitchingTests.smaller)
        while store.isDraining || store.loadedDescriptor?.id != ModelSwitchingTests.smaller.id { await store.settle() }

        #expect(store.history.map(\.modelID) == [ModelCatalog.default.id])
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.smaller.id)
        #expect(store.state == .ready)
    }

    @Test("queued work for two models runs in order, swapping once between them")
    func mixedQueueSwapsBetweenItems() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a"
        store.generate()
        store.settings.prompt = "b"
        store.generate()
        store.switchModel(to: ModelSwitchingTests.smaller)
        store.settings.prompt = "c"
        store.generate()
        #expect(store.queue.map(\.model.id) == [ModelCatalog.default.id, ModelSwitchingTests.smaller.id])

        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["c", "b", "a"])
        #expect(store.history.map(\.modelID) == [ModelSwitchingTests.smaller.id, ModelCatalog.default.id, ModelCatalog.default.id])
        #expect(bed.control.settings.loads == 2)
        #expect(bed.control.settings.unloads == 1)
    }

    @Test("two quick picks settle on the second model with the first never loaded")
    func twoQuickPicksSettleOnTheSecond() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(30) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.switchModel(to: ModelSwitchingTests.smaller)
        store.switchModel(to: ModelCatalog.default)
        while store.state != .ready || store.loadedDescriptor?.id != ModelCatalog.default.id {
            await store.settle()
        }

        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id)
        #expect(store.descriptor.id == ModelCatalog.default.id)
        #expect(bed.control.settings.loads == 2, "the abandoned pick must not load")
    }

    @Test("stop during a queued swap drops the queue and leaves the engine idle, resumable")
    func cancelDuringQueuedSwap() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20); $0.loadDelay = .milliseconds(200) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a"
        store.generate()
        try await bed.waitForFirstStep()
        store.switchModel(to: ModelSwitchingTests.smaller)
        store.settings.prompt = "b"
        store.generate()
        while !store.isSwitchingForQueue { await Task.yield() }

        store.cancel()
        await store.settle()

        #expect(store.queue.isEmpty)
        #expect(!store.isSwitchingForQueue)
        #expect(store.state == .idle || store.state == .ready)
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.smaller.id)
    }

    @Test("retry during a swap starts no second load and keeps the queue")
    func retryDuringSwapIsRefused() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20); $0.loadDelay = .milliseconds(150) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a"
        store.generate()
        try await bed.waitForFirstStep()
        store.switchModel(to: ModelSwitchingTests.smaller)
        store.settings.prompt = "b"
        store.generate()
        while !store.isSwappingModel { await Task.yield() }

        store.retry()
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(bed.control.settings.loads == 2, "retry must not add a load")
        #expect(store.history.map(\.settings.prompt) == ["b", "a"])
        #expect(!store.isSwappingModel)
    }

    @Test("switching during the initial download loads the new model exactly once")
    func switchDuringInitialDownload() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(150) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.retry()
        while store.state == .idle { await Task.yield() }

        store.switchModel(to: ModelSwitchingTests.smaller)
        while store.state != .ready || store.loadedDescriptor?.id != ModelSwitchingTests.smaller.id { await store.settle() }

        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.smaller.id)
        #expect(bed.control.settings.loads <= 2)
        #expect(!store.isSwappingModel)
    }

    @Test("a swap whose load fails drops the queue and shows the failure")
    func failedSwapDropsTheQueue() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a"
        store.generate()
        try await bed.waitForFirstStep()
        bed.control.update { $0.loadError = .loadFailed("no weights") }
        store.switchModel(to: ModelSwitchingTests.smaller)
        store.settings.prompt = "b"
        store.generate()
        while store.isDraining { await store.settle() }
        await store.settle()

        #expect(store.queue.isEmpty)
        #expect(store.state == .failed(.backend(.loadFailed("no weights"))))
        #expect(store.loadedDescriptor == nil)
        #expect(!store.isSwappingModel)
    }
}
