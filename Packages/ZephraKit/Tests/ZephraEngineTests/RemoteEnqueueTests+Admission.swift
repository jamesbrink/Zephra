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

    @Test("a store that has loaded nothing yet says so rather than blaming the request")
    func refusedWhileIdle() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
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
