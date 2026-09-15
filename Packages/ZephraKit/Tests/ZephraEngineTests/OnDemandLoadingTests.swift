import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// What a Mac set to load models only when asked does, and does not do.
///
/// The mode is read in three places — the launch, a pick in the menu, and the queue bringing the
/// loaded model in line with the chosen one once it empties. The load itself is the queue's own
/// next-entry branch, which is the same machinery a model swap mid-queue has always used.
@MainActor
@Suite("A Mac that loads models only when asked")
struct OnDemandLoadingTests {
    /// A store that has surveyed the disk and loaded nothing, which is what a launch leaves.
    static func surveyed(_ bed: EngineTestBed) async -> GenerationStore {
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.loadingMode = .onDemand
        await store.bootstrap()
        return store
    }

    @Test("the launch surveys the disk and reads no weights in")
    func bootstrapLoadsNothing() async throws {
        let bed = EngineTestBed()
        let chosen = ModelCatalog.default
        let store = await Self.surveyed(bed)

        #expect(store.state == .idle)
        #expect(bed.control.settings.loads == 0, "nothing is read in at launch")
        #expect(store.loadedDescriptor == nil)
        #expect(store.descriptor.id == chosen.id, "the chosen model stays chosen")
        #expect(!store.availability.isEmpty, "the disk is still surveyed")
        await store.shutdown()
    }

    @Test("picking a model adopts it and starts neither a download nor a load")
    func pickingAdoptsOnly() async throws {
        let bed = EngineTestBed()
        let store = await Self.surveyed(bed)
        let other = ModelSwitchingTests.otherFamily

        store.switchModel(to: other)
        await store.settle()

        #expect(store.descriptor.id == other.id)
        #expect(store.loadedDescriptor == nil)
        #expect(bed.control.settings.loads == 0)
        #expect(store.downloads.items.isEmpty, "a pick is a pick, not a transfer")
        #expect(store.state == .idle)
        await store.shutdown()
    }

    @Test("Generate loads the chosen model first and then runs on it")
    func generateLoadsThenRuns() async throws {
        let bed = EngineTestBed()
        let store = await Self.surveyed(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        #expect(store.canQueue, "a Mac with nothing loaded still takes a press")

        store.generate()
        try await bed.waitUntil { store.history.count == 1 }
        await store.settle()

        #expect(bed.control.settings.loads == 1)
        #expect(store.loadedDescriptor?.id == store.descriptor.id)
        #expect(store.state == .ready)
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("a second press during that load queues behind it rather than loading again")
    func asecondPressQueuesBehindTheLoad() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(300) }
        let store = await Self.surveyed(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2

        store.generate()
        try await bed.waitFor(store, toReach: .loading(.preparing))
        store.generate()
        #expect(store.queue.count == 2, "both wait for the one load")

        bed.control.update { $0.loadDelay = .zero }
        try await bed.waitUntil { store.history.count == 2 }
        await store.settle()
        #expect(bed.control.settings.loads == 1, "one press's load serves both")
        await store.shutdown()
    }

    @Test("Stop during that load drops the entry and leaves the Mac idle with nothing loaded")
    func stopDuringTheLoad() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(500) }
        let store = await Self.surveyed(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2

        store.generate()
        try await bed.waitFor(store, toReach: .loading(.preparing))
        store.cancel()
        await store.settle()

        #expect(store.state == .idle)
        #expect(store.queue.isEmpty, "the entry goes with the load it was waiting for")
        #expect(store.loadedDescriptor == nil)
        #expect(store.history.isEmpty)
        await store.shutdown()
    }

    @Test("a load that fails empties the queue and says why")
    func afailedLoadEmptiesTheQueue() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadError = .loadFailed("no weights here") }
        let store = await Self.surveyed(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2

        store.generate(count: 2)
        await store.settle()

        #expect(store.state == .failed(.backend(.loadFailed("no weights here"))))
        #expect(store.queue.isEmpty, "nothing waits behind a model that will not load")
        #expect(store.history.isEmpty)
        await store.shutdown()
    }

    @Test("Automatic is unchanged: the launch loads and a pick swaps the weights")
    func automaticStillLoadsAtLaunch() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        #expect(store.loadingMode == .automatic, "a store nobody told behaves as it always has")

        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 1)

        store.switchModel(to: ModelSwitchingTests.otherFamily)
        await store.settle()
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        #expect(bed.control.settings.loads == 2)
        await store.shutdown()
    }
}
