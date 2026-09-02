import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore model switching")
struct ModelSwitchingTests {
    /// A second model for the same backend, narrower than the catalog's in every direction, so
    /// a switch to it has something to clamp.
    static let smaller = ModelDescriptor(
        id: "test-smaller",
        displayName: "Test Model",
        variantName: "small",
        backend: .zImage,
        source: .huggingFace(repoID: "example/test-small", revision: "main", filePatterns: ["*"]),
        quantization: .int4,
        downloadBytes: 4_000_000_000,
        residentBytes: 4_000_000_000,
        peakBytes: 8_000_000_000,
        tiledPeakBytes: 6_000_000_000,
        maxPromptTokens: 128,
        capabilities: ModelCapabilities(
            sizeAlignment: 64,
            sizePresets: [ImageSize(width: 512, height: 512)],
            sizeBounds: 256...512,
            defaultSize: ImageSize(width: 512, height: 512),
            stepBounds: 1...4,
            defaultSteps: 2,
            guidanceBounds: 1...8,
            defaultGuidance: 4,
            supportsNegativePrompt: true,
            supportsSeed: true
        )
    )

    @Test("switching clamps the settings to the new model, keeping the prompt and the seed")
    func switchClampsSettings() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.size = ImageSize(width: 1344, height: 768)
        store.settings.steps = 9
        let seed = store.settings.seed

        store.switchModel(to: Self.smaller)
        await store.settle()

        #expect(store.descriptor.id == Self.smaller.id)
        #expect(store.settings.prompt == "a lighthouse")
        #expect(store.settings.seed == seed)
        #expect(store.settings.size == ImageSize(width: 512, height: 512))
        #expect(store.settings.steps == 4)
        #expect(store.settings.guidance == 1)
        #expect(store.state == .ready)
    }

    @Test("switching unloads the old model before loading the new one")
    func switchUnloadsThenLoads() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.unloads == 0)

        store.switchModel(to: Self.smaller)
        await store.settle()

        #expect(bed.control.settings.unloads == 1, "the old weights must go back first")
        #expect(bed.control.settings.loads == 2)
    }

    @Test("switching to the model already loaded does nothing at all")
    func switchToSameModelIsANoOp() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.switchModel(to: ModelCatalog.default)
        await store.settle()

        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.unloads == 0)
    }

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

        store.switchModel(to: Self.smaller)
        #expect(store.descriptor.id == Self.smaller.id, "the choice lands at once")
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "the run keeps its model")
        #expect(store.state.isBusy)
        store.settings.prompt = "second"
        store.generate()
        #expect(store.queue.first?.model.id == Self.smaller.id)

        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["second", "first"])
        #expect(store.history.map(\.modelID) == [Self.smaller.id, ModelCatalog.default.id])
        #expect(bed.control.settings.unloads == 1)
        #expect(bed.control.settings.loads == 2)
        #expect(store.loadedDescriptor?.id == Self.smaller.id)
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

        store.switchModel(to: Self.smaller)
        while store.isDraining || store.loadedDescriptor?.id != Self.smaller.id { await store.settle() }

        #expect(store.history.map(\.modelID) == [ModelCatalog.default.id])
        #expect(store.loadedDescriptor?.id == Self.smaller.id)
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
        store.switchModel(to: Self.smaller)
        store.settings.prompt = "c"
        store.generate()
        #expect(store.queue.map(\.model.id) == [ModelCatalog.default.id, Self.smaller.id])

        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["c", "b", "a"])
        #expect(store.history.map(\.modelID) == [Self.smaller.id, ModelCatalog.default.id, ModelCatalog.default.id])
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

        store.switchModel(to: Self.smaller)
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
        store.switchModel(to: Self.smaller)
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
        #expect(store.loadedDescriptor?.id == Self.smaller.id)
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
        store.switchModel(to: Self.smaller)
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

        store.switchModel(to: Self.smaller)
        while store.state != .ready || store.loadedDescriptor?.id != Self.smaller.id { await store.settle() }

        #expect(store.loadedDescriptor?.id == Self.smaller.id)
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
        store.switchModel(to: Self.smaller)
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
