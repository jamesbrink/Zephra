import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The canvas follows the run it was asked for, and stops following when the user looks
/// elsewhere. `current` is what is on the canvas; it is no longer whatever the engine made last.
@Suite("following the run")
@MainActor
struct FollowingRunTests {
    @Test("pressing Generate follows the run, and its frames land in the live preview")
    func generateFollowsAndFramesArrive() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        #expect(store.followsRun)
        #expect(store.isShowingRun)
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        #expect(store.livePreview?.width == 2)

        await store.settle()
        #expect(store.livePreview == nil, "a finished run leaves no frame behind")
        #expect(store.current?.pngData == MockBackend.pngData)
        #expect(!store.isShowingRun, "nothing is running any more")
    }

    @Test("a result that lands while the user is looking elsewhere leaves the canvas alone")
    func aResultDoesNotYankTheCanvas() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: store.settings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        #expect(!store.followsRun)
        await store.settle()

        #expect(store.current?.id == earlier.id, "the picture being looked at stayed")
        #expect(store.history.count == 1, "the result still entered history")
        #expect(store.history.first?.pngData == MockBackend.pngData)
        #expect(try bed.writtenFiles().count == 1, "and was still written")
    }

    @Test("watching the run again puts its result back on the canvas")
    func watchRunFollowsAgain() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: store.settings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        store.watchRun()
        #expect(store.isShowingRun)
        await store.settle()

        #expect(store.current?.pngData == MockBackend.pngData)
    }

    @Test("opening a library picture stops the canvas following, and the frame stays with the run")
    func openingStopsFollowing() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.stopFollowingRun()

        #expect(!store.followsRun)
        #expect(store.livePreview != nil, "the run's frame is still the card's to show")
        #expect(!store.isShowingRun)
        await store.settle()
    }

    @Test("queueing another run behind the one in flight keeps its frame on the canvas")
    func queueingKeepsTheFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.generate()

        #expect(store.queue.count == 1)
        #expect(store.livePreview != nil, "the frame belongs to the run, not to the press")
        #expect(store.isShowingRun)
        await store.settle()
    }

    @Test("a run that is stopped puts its frame down at once")
    func cancellingDropsTheFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update {
            $0.previewsEveryStep = true
            $0.stepDelay = .milliseconds(10)
            $0.stepOverride = 200
        }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.cancel()

        #expect(store.livePreview == nil)
        await store.settle()
        #expect(store.current == nil, "a stopped run publishes nothing")
    }

    @Test("the frame of one run never opens the next")
    func aNewRunStartsWithNoFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        await store.settle()
        #expect(bed.control.settings.previewsEmitted > 0, "the mock did report frames")
        #expect(store.livePreview == nil)

        store.generate()
        #expect(store.livePreview == nil, "the new run starts blank")
        await store.settle()
    }

    /// Blocks until a frame has made it through the pump to the main actor, which is a moment
    /// behind the backend reporting it.
    private func waitForPreview(on store: GenerationStore) async throws {
        for _ in 0..<500 {
            if store.livePreview != nil { return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

/// The sidebar's wall and its running card are both a run to pick up again, so both move the
/// capsule's settings, not only the canvas.
@Suite("picking a run up again from the sidebar")
@MainActor
struct SidebarSelectionTests {
    @Test("selecting a library picture shows it and adopts its settings; opening only shows it")
    func selectAdoptsAndOpenDoesNot() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try bed.library.write(LibraryAnnotationTests.image(seed: 11, prompt: "a harbour"))
        let item = try #require(LibraryScan(library: bed.library).rescan().first)
        store.settings.prompt = "a lighthouse"

        await store.open(item)
        #expect(store.current?.settings.prompt == "a harbour")
        #expect(store.settings.prompt == "a lighthouse", "looking adopts nothing")

        await store.select(item)
        #expect(store.current?.settings.prompt == "a harbour")
        #expect(store.settings.prompt == "a harbour")
        #expect(store.settings.seed == 11)
        #expect(!store.followsRun)
    }

    @Test("watching the run again puts the run's own settings back in the capsule")
    func watchRunRestoresTheRunsSettings() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.seed = 7
        var earlierSettings = store.settings
        earlierSettings.prompt = "a harbour"
        earlierSettings.seed = 11
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: earlierSettings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        #expect(store.settings.prompt == "a harbour")
        #expect(store.settings.seed == 11)

        store.watchRun()
        #expect(store.isShowingRun)
        #expect(store.settings.prompt == "a lighthouse")
        #expect(store.settings.seed == 7)
        await store.settle()
    }

    @Test("with nothing running, watching again changes no settings")
    func watchRunWithNothingRunning() async {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.watchRun()
        #expect(store.settings.prompt == "a lighthouse")
    }
}

/// A picture's model is chosen when the picture is, and loaded only when Generate asks.
@Suite("a picture's model waits for Generate")
@MainActor
struct DeferredModelTests {
    @Test("selecting another model's picture chooses its model without loading it")
    func selectingChoosesWithoutLoading() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let loads = bed.control.settings.loads
        var settings = GenerationSettings.defaults(for: other)
        settings.prompt = "made elsewhere"
        let picture = GeneratedImage(
            pngData: Data([1]), settings: settings, modelID: other.id, duration: .seconds(1))

        store.select(picture)
        await store.settle()

        #expect(store.descriptor.id == other.id, "the menu says what Generate will run")
        #expect(store.modelAwaitsGenerate)
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "nothing was swapped")
        #expect(store.rememberedModel.id == ModelCatalog.default.id, "a picture looked at is not a model used")
        #expect(bed.control.settings.loads == loads)
        #expect(store.state == .ready)

        store.generate()
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(!store.modelAwaitsGenerate)
        #expect(store.loadedDescriptor?.id == other.id, "Generate is what loaded it")
        #expect(store.history.map(\.modelID) == [other.id])
        #expect(store.rememberedModel.id == other.id)
    }

    @Test("a picture chosen while the launch's model is still loading remembers the loading one")
    func selectingDuringALoad() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(150) }
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        let loading = Task { await store.bootstrap() }
        try await bed.waitFor(store, toReach: .loading(.preparing))
        let picture = GeneratedImage(
            pngData: Data([1]), settings: .defaults(for: other), modelID: other.id,
            duration: .seconds(1))

        store.select(picture)

        #expect(store.descriptor.id == other.id)
        #expect(store.modelAwaitsGenerate)
        #expect(store.rememberedModel.id == ModelCatalog.default.id, "the one on its way in, not the picture's")
        await loading.value
        await store.settle()
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "the load finished on its own model")
        #expect(store.state == .ready)
        #expect(store.rememberedModel.id == ModelCatalog.default.id)
    }

    @Test("picking the loaded model back in the menu swaps nothing")
    func pickingTheLoadedModelBack() async throws {
        let bed = EngineTestBed()
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let picture = GeneratedImage(
            pngData: Data([1]), settings: .defaults(for: other), modelID: other.id,
            duration: .seconds(1))
        store.select(picture)
        let unloads = bed.control.settings.unloads

        store.switchModel(to: ModelCatalog.default)
        await store.settle()

        #expect(store.descriptor.id == ModelCatalog.default.id)
        #expect(!store.modelAwaitsGenerate)
        #expect(bed.control.settings.unloads == unloads)
        #expect(store.state == .ready)
    }

    @Test("a run's end does not swap to a model chosen only by a picture")
    func aRunsEndLeavesTheLoadedModel() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let picture = GeneratedImage(
            pngData: Data([1]), settings: .defaults(for: other), modelID: other.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(picture)
        #expect(store.descriptor.id == other.id)
        await store.settle()

        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id)
        #expect(bed.control.settings.unloads == 0)
        #expect(store.state == .ready)

        store.watchRun()
        #expect(store.descriptor.id == other.id, "with nothing running there is nothing to restore")
    }

    @Test("watching the run again puts the run's model back")
    func watchRunRestoresTheModel() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let picture = GeneratedImage(
            pngData: Data([1]), settings: .defaults(for: other), modelID: other.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(picture)
        store.watchRun()

        #expect(store.descriptor.id == ModelCatalog.default.id)
        #expect(!store.modelAwaitsGenerate)
        #expect(store.settings.prompt == "a lighthouse")
        await store.settle()
    }
}

/// What the review of the deferred model found and pinned.
@Suite("a picture's model, at the edges")
@MainActor
struct DeferredModelEdgeTests {
    private let other = ModelCatalog.zImageTurbo4bit

    private func picture(of model: ModelDescriptor) -> GeneratedImage {
        GeneratedImage(
            pngData: Data([1]), settings: .defaults(for: model), modelID: model.id,
            duration: .seconds(1))
    }

    @Test("Try Again after a failed run swaps to the picture's model and gives the old lease back")
    func retryAfterAFailureSwaps() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero; $0.generateError = .generationFailed("kernel panic") }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.generate()
        while store.isRunning { await store.settle() }
        guard case .failed = store.state else { Issue.record("the run did not fail"); return }
        store.select(picture(of: other))
        #expect(store.modelAwaitsGenerate)

        store.retry()
        await store.settle()

        #expect(store.loadedDescriptor?.id == other.id)
        #expect(bed.control.settings.unloads == 1, "the old model's weights went back first")
        #expect(!store.modelAwaitsGenerate, "the load landed on the chosen model")
        #expect(store.state == .ready)
    }

    @Test("picking the chosen-but-unloaded model in the menu is what loads it")
    func pickingTheWaitingModelLoadsIt() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.select(picture(of: other))
        #expect(store.modelAwaitsGenerate)

        store.switchModel(to: other)
        await store.settle()

        #expect(!store.modelAwaitsGenerate)
        #expect(store.loadedDescriptor?.id == other.id)
        #expect(store.state == .ready)
    }

    @Test("watching the run leaves a capsule the user has been working in alone")
    func watchRunLeavesTheUsersCapsule() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.generate()
        try await bed.waitForStep()
        store.switchModel(to: other)
        store.settings.prompt = "the next one"
        store.stopFollowingRun()

        store.watchRun()

        #expect(store.isShowingRun)
        #expect(store.descriptor.id == other.id, "the menu pick stands")
        #expect(store.settings.prompt == "the next one", "and so does the prompt")
        while store.isDraining || store.isSwappingModel { await store.settle() }
        await store.settle()
        #expect(store.loadedDescriptor?.id == other.id, "the pick landed when the run ended")
    }

    @Test("a menu pick made while a square's file is still being read wins")
    func menuPickBeatsARead() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        try bed.library.write(LibraryAnnotationTests.image(seed: 11, prompt: "a harbour"))
        let item = try #require(LibraryScan(library: bed.library).rescan().first)
        store.settings.prompt = "a lighthouse"

        let read = Task { await store.select(item) }
        // The click's task has started and is waiting on the file by the time a menu pick
        // could follow it; the yield stands for the event loop's turn between the two.
        try await Task.sleep(for: .milliseconds(1))
        store.switchModel(to: other)
        await read.value
        await store.settle()

        #expect(store.descriptor.id == other.id)
        #expect(store.settings.prompt == "a lighthouse", "the read was abandoned")
    }
}
