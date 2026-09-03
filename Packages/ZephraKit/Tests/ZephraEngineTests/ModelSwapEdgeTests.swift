import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The awkward moments of a model swap: two picks in a row, Stop or retry in the middle of one,
/// a switch during the first download, and a swap whose load fails.
@MainActor
@Suite("GenerationStore model swap edge cases")
struct ModelSwapEdgeTests {
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
        try await bed.waitForStep()
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
        try await bed.waitForStep()
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
        try await bed.waitForStep()
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
