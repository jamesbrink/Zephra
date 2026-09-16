import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// What a lost GPU costs: the launch, not the run.
///
/// `BackendError.deviceFailed` is the recoverable fault `DeviceFaultTests` pins — the weights
/// stay up and Try Again works. This is the other one, measured on a 16 GB mini: the driver
/// stops running this process's command buffers altogether, and an unload, a reload and a
/// switch to another model each failed in a third of a second for four minutes. So the store
/// stops submitting anything at all, including the submissions an unload would make, and the
/// app relaunches instead.
@MainActor
@Suite("A GPU the driver has stopped running this process's work on")
struct DeviceLossTests {
    /// The text a runtime hands up with an ignored submission, as MLX composes it.
    static let message =
        "[METAL] Command buffer execution failed: Ignored (for causing prior/excessive GPU "
        + "errors) (00000004:kIOGPUCommandBufferCallbackErrorSubmissionsIgnored)."

    /// A store that has loaded a model and then lost the GPU to one generation.
    static func lostStore(_ bed: EngineTestBed) async -> GenerationStore {
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.generateError = .deviceLost(Self.message) }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()
        return store
    }

    @Test("the run fails with the one sentence and nothing else may be started")
    func lossClosesAdmission() async throws {
        let bed = EngineTestBed()
        let store = await Self.lostStore(bed)

        #expect(store.state == .failed(.deviceLost))
        #expect(
            EngineError.deviceLost.message
                == "Zephra has lost the GPU and has to relaunch to get it back.")
        #expect(store.deviceLost)
        #expect(!store.acceptsWork)
        #expect(!store.canLoad(store.descriptor))
        #expect(!store.canUnload)
        #expect(!store.canUpscale)
        #expect(!store.canQueue)
        #expect(!store.acceptsQueuedGeneration)
        #expect(store.history.isEmpty, "a run the GPU refused keeps nothing")
        await store.shutdown()
    }

    @Test("a load event arriving late does not paint over the lost state")
    func aLateLoadEventIsDropped() async throws {
        let bed = EngineTestBed()
        let store = await Self.lostStore(bed)

        store.applyLoadEvent(.progress(GenerationProgressEvent(phase: .preparing, fraction: 0)))
        #expect(store.state == .failed(.deviceLost))
        await store.shutdown()
    }

    @Test("Try Again loads nothing, whatever the backend would have done")
    func retryDoesNotReload() async throws {
        let bed = EngineTestBed()
        let store = await Self.lostStore(bed)
        let loadsBefore = bed.control.settings.loads

        // The very thing a person presses twice in ten seconds, and the thing that failed in
        // a third of a second each time on bender.
        store.retry()
        store.loadModel()
        await store.settle()

        #expect(bed.control.settings.loads == loadsBefore, "nothing may be read in again")
        #expect(store.state == .failed(.deviceLost), "and the sentence stays up")
        await store.shutdown()
    }

    @Test("quitting gives nothing back, since that is one more submission the driver refuses")
    func shutdownDoesNotUnload() async throws {
        let bed = EngineTestBed()
        let store = await Self.lostStore(bed)
        let unloadsBefore = bed.control.settings.unloads
        let releasesBefore = bed.control.settings.cacheReleases

        await store.shutdown()

        #expect(bed.control.settings.unloads == unloadsBefore)
        #expect(bed.control.settings.cacheReleases == releasesBefore)
    }

    @Test("the idle clock does not fire over it")
    func idleUnloadDoesNotFire() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.idleWait = { _ in }
        await store.bootstrap()
        store.idleUnloadDelay = .fiveMinutes

        bed.control.update { $0.generateError = .deviceLost(Self.message) }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()
        let unloads = bed.control.settings.unloads
        // Long enough for a clock that was still armed to have run several times over.
        for _ in 0..<20 { await Task.yield() }

        #expect(bed.control.settings.unloads == unloads)
        #expect(store.state == .failed(.deviceLost))
        await store.shutdown()
    }

    @Test("a paired phone is refused in the Mac's own words")
    func aPhoneHearsTheSentence() async throws {
        let bed = EngineTestBed()
        let store = await Self.lostStore(bed)
        var settings = GenerationSettings.defaults(for: store.descriptor)
        settings.prompt = "a lighthouse"

        let admission = store.remoteAdmission(for: store.descriptor, settings: settings)

        #expect(admission == .refused(EngineError.deviceLost.message))
        #expect(store.enqueue(settings, on: store.descriptor) == nil)
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("a fault the device recovers from is still only a lost run")
    func aPlainFaultIsNotALoss() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        bed.control.update { $0.deviceFaultAtStep = 1; $0.stepDelay = .zero }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()

        #expect(!store.deviceLost, "an innocent victim is not an ignored submission")
        #expect(store.acceptsWork)
        #expect(store.canLoad(store.descriptor))
        await store.shutdown()
    }

    @Test("the latch closing with nothing running is noticed at the next state change")
    func theLatchIsNoticedWithoutAThrow() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let unloads = bed.control.settings.unloads

        // The path bender actually took: the driver stopped answering inside `releaseCache`
        // during an unload, so nothing threw and the store heard about it only when something
        // next transitioned. `unloadModel` is that something here, and it is also the window
        // the flag bookkeeping is about: `canUnload` is read before the latch is polled.
        bed.control.update { $0.deviceLost = true }
        store.unloadModel()
        await store.settle()

        #expect(store.deviceLost, "the runtime's latch is what says so, not a thrown error")
        #expect(store.state == .failed(.deviceLost))
        #expect(!store.acceptsWork)
        #expect(!store.canLoad(store.descriptor))
        #expect(!store.isSwappingModel, "a flag raised for a task that never ran")
        #expect(bed.control.settings.unloads == unloads, "and the weights were not handed back")
        await store.shutdown()
    }

    @Test("a run already on the actor is cancelled where it stands")
    func whatIsInFlightIsCancelled() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(20); $0.stepOverride = 200 }
        store.settings.prompt = "a lighthouse"
        store.generate()
        try await bed.waitUntil { store.running != nil }

        bed.control.update { $0.deviceLost = true }
        // Any state change is where the latch is read; on a Mac left alone the next one arrives
        // on its own, from a download settling or the run itself ending.
        store.transition(to: .idle)

        #expect(store.generationTask?.isCancelled == true, "it submits nothing more")
        #expect(store.running == nil)
        #expect(store.queue.isEmpty)
        await store.settle()
        #expect(store.state == .failed(.deviceLost))
        #expect(store.history.isEmpty, "a run the GPU lost keeps nothing")
        await store.shutdown()
    }

    @Test("a load already under way is cancelled too")
    func aLoadInFlightIsCancelled() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        bed.control.update { $0.loadDelay = .seconds(5) }
        let booting = Task { await store.bootstrap() }
        try await bed.waitUntil { store.bootstrapTask != nil }

        bed.control.update { $0.deviceLost = true }
        store.transition(to: .idle)

        #expect(store.bootstrapTask?.isCancelled == true, "the weights stop being read in")
        await booting.value
        #expect(store.state == .failed(.deviceLost))
        #expect(bed.control.settings.unloads == 0, "and the failed load undoes nothing either")
        await store.shutdown()
    }

    @Test("a load that is what discovers the loss undoes nothing")
    func aLostLoadDoesNotUnload() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        // The one path guaranteed to be taken when a load is what finds the driver gone: the
        // catch that used to run `inference.unload()` — the backend's arrays dropped, Metal
        // synchronized, the allocator's cache handed back — before the error was classified.
        // Both dials, because a real `.deviceLost` *is* the latch: `MLXInferenceRuntime.failure`
        // composes it by reading `DeviceFaultSink.faults`, so a runtime that throws it and one
        // that answers `isDeviceLost` false is a Mac that cannot exist.
        bed.control.update { $0.loadError = .deviceLost(Self.message); $0.deviceLost = true }

        await store.bootstrap()
        await store.settle()

        #expect(store.deviceLost)
        #expect(store.state == .failed(.deviceLost))
        #expect(bed.control.settings.unloads == 0, "three submissions into a refusing channel")
        #expect(!store.acceptsWork)
        await store.shutdown()
    }
}

