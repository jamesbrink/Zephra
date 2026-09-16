import Foundation
import Synchronization
import Testing
import ZephraCore

@testable import ZephraEngine
@testable import ZephraSnapshot

@MainActor
@Suite("Nothing new begins while storage is unsettled")
struct AdmissionGateTests {
    @Test("a variation is refused while the app is shutting down")
    func variationRefusedDuringShutdown() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let generations = bed.control.settings.generations
        store.isShuttingDown = true

        store.queueVariation(of: LibraryFilteringTests.item(prompt: "a lighthouse"))
        await store.settle()

        #expect(store.queue.isEmpty)
        #expect(bed.control.settings.generations == generations)
        #expect(store.state == .ready)
        store.isShuttingDown = false
        await store.shutdown()
    }

    @Test("a variation is refused while model storage is being deleted")
    func variationRefusedDuringDeletion() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let generations = bed.control.settings.generations
        store.deletionInProgress = true

        store.queueVariation(of: LibraryFilteringTests.item(prompt: "a lighthouse"))
        await store.settle()

        #expect(store.queue.isEmpty)
        #expect(bed.control.settings.generations == generations)
        store.deletionInProgress = false
        await store.shutdown()
    }

    @Test("a variation cancels a reference still on its way")
    func variationCancelsAReferenceRead() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        try #require(store.descriptor.capabilities.supportsReferenceImage)
        let release = AsyncStream<Void>.makeStream()
        store.adoptReference {
            for await _ in release.stream {}
            return Data([1])
        }
        let read = store.referenceRead
        #expect(store.isAdoptingReference)

        store.queueVariation(of: LibraryFilteringTests.item(prompt: "a lighthouse"))
        #expect(!store.isAdoptingReference, "the variation's own reference is what runs")
        release.continuation.finish()
        await read?.value
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.settings.referenceImage == nil, "the record had no picture, so none runs")
        #expect(bed.control.settings.lastSettings?.referenceImage == nil)
        await store.shutdown()
    }

    @Test("a Mac with nothing loaded takes a press, and one with nothing to load does not")
    func canQueueWithNothingLoaded() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.loadingMode = .onDemand
        await store.bootstrap()
        #expect(store.state == .idle)
        #expect(!store.canQueue, "still nothing to run without a prompt")

        store.settings.prompt = "a lighthouse"
        #expect(store.canQueue, "the queue loads what the entry needs before it runs it")
        #expect(store.canLoad(store.descriptor))

        // A model that is not on the disk at all is the one case that still refuses.
        bed.control.update {
            for model in ModelCatalog.all { $0.availability[model.id] = .missing(reason: "gone") }
        }
        await store.refreshAvailability()
        #expect(!store.canLoad(store.descriptor))
        #expect(!store.canQueue)
        await store.shutdown()
    }

    @Test("the queue resumes once a deletion has finished")
    func queueResumesAfterDeletion() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let entered = Mutex(false)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let inventory = ModelInventory(
            catalog: [], locations: store.modelLocations,
            remove: { _ in
                entered.withLock { $0 = true }
                gate.wait()
            })
        let item = ModelStorageItem(
            name: "unused", kind: .built, url: bed.directory.appending(path: "unused"),
            location: "unused", modelIDs: [], isComplete: true)
        store.settings.prompt = "x"
        store.settings.steps = 2
        store.generate(count: 2)
        try await bed.waitForStep()
        let deleting = Task { await store.deleteModelStorage(item, inventory: inventory) }
        try await bed.waitUntil { entered.withLock { $0 } }
        // The first image lands while the deletion holds; the queue may not move yet.
        try await bed.waitUntil { store.history.count == 1 }
        await store.generationTask?.value
        #expect(store.state == .ready)
        #expect(store.queue.count == 1, "the second waits for the deletion")
        #expect(store.running == nil)

        gate.signal()
        await deleting.value
        // Bounded rather than a settle loop: a queue that never moves again would spin forever.
        try await bed.waitUntil(.seconds(5)) { store.history.count == 2 }
        await store.settle()

        #expect(store.history.count == 2, "the deletion's exit drained the queue")
        #expect(try bed.writtenFiles().count == 2)
        await store.shutdown()
    }
}
