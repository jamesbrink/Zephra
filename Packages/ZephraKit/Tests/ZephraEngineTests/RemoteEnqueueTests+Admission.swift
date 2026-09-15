import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// What a device is told when its request cannot be queued: the three refusals, and that each
/// of them also stops `enqueue` from putting anything in the queue.
extension RemoteEnqueueTests {
    @Test("a folder change answers busy, and queues nothing")
    func busyDuringAFolderChange() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.modelDirectoryProgress = "Moving models"
        let models = store.remoteAdmission(for: ModelCatalog.default)
        #expect(models == .busy("Zephra is changing its models folder."))
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) == nil)
        #expect(store.queue.isEmpty)

        store.modelDirectoryProgress = nil
        store.imageDirectoryProgress = "Moving images"
        #expect(
            store.remoteAdmission(for: ModelCatalog.default)
                == .busy("Zephra is changing its images folder."))

        store.imageDirectoryProgress = nil
        #expect(store.remoteAdmission(for: ModelCatalog.default) == .admitted)
        await store.shutdown()
    }

    @Test("a load in flight answers refused, and queues nothing")
    func refusedWhileLoading() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(500) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        let bootstrap = Task { await store.bootstrap() }
        try await bed.waitFor(store, toReach: .loading(.preparing))

        #expect(
            store.remoteAdmission(for: ModelCatalog.default)
                == .refused("Zephra is preparing a model."))
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) == nil)
        #expect(store.queue.isEmpty)

        bed.control.update { $0.loadDelay = .zero }
        await bootstrap.value
        await store.settle()
        #expect(store.remoteAdmission(for: ModelCatalog.default) == .admitted)
        await store.shutdown()
    }

    @Test("a store that has loaded nothing yet takes the request and loads what it needs")
    func idleTakesTheRequestAndLoads() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.loadingMode = .onDemand
        await store.bootstrap()
        #expect(store.state == .idle)
        #expect(store.loadedDescriptor == nil)

        #expect(
            store.remoteAdmission(for: ModelCatalog.default, settings: Self.request())
                == .admitted)
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) != nil)
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id)
        #expect(store.history.count == 1, "the queue loaded the model and then ran the entry")
        await store.shutdown()
    }

    @Test("a model that is not on the disk to load is refused, and queues nothing")
    func refusedWhenNothingIsObtainable() async throws {
        let bed = EngineTestBed()
        bed.control.update {
            $0.availability[ModelCatalog.default.id] = .missing(reason: "never built")
        }
        let store = bed.store()
        store.loadingMode = .onDemand
        await store.refreshAvailability()

        #expect(
            store.remoteAdmission(for: ModelCatalog.default, settings: Self.request())
                == .refused("No model is loaded yet."))
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) == nil)
        #expect(store.queue.isEmpty)
    }

    @Test("a count of none, an empty prompt and an unknown model are all bad requests")
    func badRequests() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let model = ModelCatalog.default

        let none = store.remoteAdmission(for: model, settings: Self.request(), count: 0)
        #expect(none == .badRequest("Ask for between 1 and \(GenerationStore.batchLimit) images at a time."))
        #expect(store.enqueue(Self.request(), on: model, count: 0) == nil)

        let tooMany = store.remoteAdmission(
            for: model, settings: Self.request(), count: GenerationStore.batchLimit + 1)
        #expect(tooMany.reason == none.reason, "either end of the range is the same answer")

        let blank = store.remoteAdmission(for: model, settings: Self.request(prompt: "   \n"))
        #expect(blank == .badRequest("Write a prompt first."))
        #expect(store.enqueue(Self.request(prompt: "   \n"), on: model) == nil)

        let stranger = store.remoteAdmission(for: Self.unknown, settings: Self.request())
        #expect(
            stranger
                == .badRequest("This Mac's Zephra does not know a model called test-not-in-the-catalog."))
        #expect(store.enqueue(Self.request(), on: Self.unknown) == nil)

        #expect(store.queue.isEmpty)
        #expect(store.state == .ready, "nothing about a refused request disturbs the engine")
        await store.shutdown()
    }

    @Test("a run in flight takes another behind it, and says so")
    func queueableMidRun() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.acceptsQueuedGeneration, "an idle engine, before anything runs")

        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()

        #expect(store.acceptsQueuedGeneration, "and one working down its queue")
        #expect(store.remoteAdmission(for: ModelCatalog.default, settings: Self.request()) == .admitted)
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) != nil)
        #expect(store.queue.count == 1, "behind the one being rendered")

        store.cancel()
        // Bounded, and sleeping between looks: a loop that only awaits `settle()` never
        // leaves the main actor when there is nothing to settle, and the finish it waits
        // for is a main-actor task that then never runs.
        try await bed.waitUntil { !store.isDraining && store.queue.isEmpty }
        await store.shutdown()
    }

    @Test("an upscale is not a queue, so nothing may be queued behind one")
    func refusedWhileUpscaling() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 20; $0.tileDelay = .milliseconds(5) }
        var settings = GenerationSettings(
            prompt: "a lighthouse at dusk", size: ImageSize(width: 1024, height: 1024),
            steps: 9, guidance: 0, seed: 99)
        settings.frames = 1
        let parent = try bed.library.write(
            GeneratedImage(
                pngData: MockBackend.pngData, settings: settings,
                modelID: ModelCatalog.default.id, duration: .seconds(3)))

        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()

        #expect(!store.acceptsQueuedGeneration, "no model need even be loaded for an upscale")
        #expect(
            store.remoteAdmission(for: ModelCatalog.default, settings: Self.request())
                == .refused("Zephra is upscaling a picture."))
        #expect(store.enqueue(Self.request(), on: ModelCatalog.default) == nil)
        #expect(store.queue.isEmpty)

        await store.settle()
        await store.shutdown()
    }

    @Test("a bad request is named as one even while the Mac is busy with something else")
    func badRequestBeatsBusy() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.isShuttingDown = true

        // Telling a phone to wait for a quit that will never make its empty prompt runnable
        // helps nobody, so the request's own fault is what it hears about.
        let blank = store.remoteAdmission(for: ModelCatalog.default, settings: Self.request(prompt: ""))
        #expect(blank == .badRequest("Write a prompt first."))
        #expect(
            store.remoteAdmission(for: ModelCatalog.default, settings: Self.request())
                == .busy("Zephra is quitting."))

        store.isShuttingDown = false
        await store.shutdown()
    }
}
