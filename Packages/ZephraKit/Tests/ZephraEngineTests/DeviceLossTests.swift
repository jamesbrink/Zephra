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
}
