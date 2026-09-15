import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine
@testable import ZephraSnapshot

/// Giving the weights back by hand, and what that leaves behind.
///
/// The chosen model stays chosen: an unload is about memory, not about which model this Mac is
/// set up to run. What it does give back is the disk lease, which is what makes the model's
/// storage deletable in Settings again.
@MainActor
@Suite("Unloading the model by hand")
struct ModelUnloadTests {
    @Test("unloading gives the lease back once, keeps the chosen model, and lands idle")
    func unloadReleasesOnceAndKeepsTheChoice() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let chosen = store.descriptor.id
        let directory = try #require(store.loadedDirectory)
        let claim = try #require(bed.control.settings.lastAcquisitionID)
        let item = ModelStorageItem(
            name: "z", kind: .download, url: directory, location: "x",
            modelIDs: [chosen], isComplete: true)
        #expect(store.modelStorageIsInUse(item))
        #expect(store.canUnload)

        store.unloadModel()
        await store.settle()

        #expect(store.state == .idle)
        #expect(store.loadedDescriptor == nil)
        #expect(store.loadedDirectory == nil)
        #expect(store.loadedResidency == nil)
        #expect(store.descriptor.id == chosen, "the chosen model stays chosen")
        #expect(bed.control.settings.unloads == 1)
        #expect(await store.downloads.transfers.claims[claim] == nil, "the lease goes back")
        #expect(!store.downloads.isRetained(claim))
        #expect(!store.modelStorageIsInUse(item), "its storage is deletable again")
        #expect(!store.isSwappingModel, "nothing is left half-swapped")
        #expect(!store.canUnload, "there is nothing left to unload")
        await store.shutdown()
    }

    @Test("Load after an unload reads the same model back in, holding one lease")
    func loadAfterUnload() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.unloadModel()
        await store.settle()

        store.loadModel()
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == store.descriptor.id)
        #expect(bed.control.settings.loads == 2)
        #expect(await bed.claimCount(store) == 1)
        await store.shutdown()
    }

    @Test("Unload is refused while a run, an upscale or a swap is in flight")
    func unloadIsRefusedWhileSomethingElseIsGoing() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()
        #expect(!store.canUnload, "not while a generation is being rendered")
        store.cancel()
        try await bed.waitUntil { !store.isDraining && store.queue.isEmpty }
        await store.settle()

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
        #expect(!store.canUnload, "and not while a picture is being made larger")
        await store.settle()

        store.isShuttingDown = true
        #expect(!store.canUnload, "nor while the app is quitting")
        store.isShuttingDown = false
        await store.shutdown()
    }

    @Test("Unload does nothing at all when nothing is loaded")
    func unloadWithNothingLoaded() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.loadingMode = .onDemand
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        #expect(!store.canUnload)
        store.unloadModel()
        await store.settle()
        #expect(store.state == .idle)
        #expect(bed.control.settings.unloads == 0)
        await store.shutdown()
    }

    @Test("a request landing while the unload settles waits for it rather than racing it")
    func arequestRacingTheUnload() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        var request = GenerationSettings.defaults(for: store.descriptor)
        request.prompt = "a lantern on a jetty"
        request.steps = 2

        // No await between the two, so the unload's own task has not run yet and the weights
        // it is about to give back are still named by `loadedDescriptor`. Admitting here would
        // start a generation on weights the actor is already queued to release, so the answer
        // is the refusal, not a run.
        store.unloadModel()
        let raced = store.enqueue(request, on: store.descriptor)
        #expect(raced == nil, "a run must not start on weights already on their way out")
        #expect(store.queue.isEmpty)

        await store.settle()
        let batch = store.enqueue(request, on: store.descriptor)
        #expect(batch != nil, "and the moment the unload has settled the same request is taken")
        try await bed.waitUntil { store.history.count == 1 }
        await store.settle()

        #expect(store.history.count == 1, "one picture, not two and not none")
        #expect(store.state == .ready)
        #expect(!store.isSwappingModel, "the unload did not clear a live swap's flag")
        #expect(store.loadedDescriptor?.id == store.descriptor.id)
        #expect(await bed.claimCount(store) == 1, "one lease, however the two raced")
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("Unload is refused in every state the engine is busy with a model in")
    func unloadIsRefusedWhileTheEngineIsBusyWithAModel() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.canUnload)

        // `loadedDescriptor` can name an *earlier* model while a fresh load runs — a change of
        // models folder makes the lease this store holds no longer the loaded one — so the
        // flags alone would offer Unload there, and releasing those weights under a
        // `bootstrapTask` nobody cancelled leaves that load republishing over a store that
        // believes it unloaded. The state is what closes it, as it does for `canUpscale`.
        let busy: [EngineState] = [
            .checkingModel,
            .downloading(DownloadProgressEvent(completedFiles: 0, totalFiles: 2, fraction: 0)),
            .building(BuildProgressEvent(
                component: "transformer", completedComponents: 0, totalComponents: 3,
                fraction: 0)),
            .loading(.preparing),
            .warmingUp,
            .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)),
            .upscaling(UpscaleProgressEvent(completedTiles: 0, totalTiles: 4)),
            .cancelling,
        ]
        for state in busy {
            store.transition(to: state)
            #expect(!store.canUnload, "Unload must not be offered in \(state.logName)")
        }

        // The three states an unload is offered from, which are `canUpscale`'s three.
        for state in [EngineState.ready, .idle, .failed(.backend(.loadFailed("boom")))] {
            store.transition(to: state)
            #expect(store.canUnload, "and it is offered again in \(state.logName)")
        }
        store.transition(to: .ready)
        await store.shutdown()
    }

    @Test("a residency forced for one load does not outlive a load that never starts")
    func aforcedResidencyIsNotLeftBehind() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        // What a run-time step-down leaves behind for the reload it asked for. `.ready` is not
        // a state a load starts from, so this attempt does nothing at all — and must not leave
        // the forcing for whatever loads next.
        store.residencyOverride = .streamed
        store.retry()
        #expect(store.residencyOverride == nil)

        store.unloadModel()
        await store.settle()
        store.loadModel()
        await store.settle()
        #expect(store.loadedResidency == .resident, "the next load is the one the policy asked for")
        #expect(bed.control.settings.lastResidency == .resident)
        await store.shutdown()
    }
}
