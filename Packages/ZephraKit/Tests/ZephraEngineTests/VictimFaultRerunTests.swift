import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// A run the GPU discarded for another process's fault goes again, once, by itself.
///
/// The case is bender's: WindowServer faults under Screen Sharing, the driver resets the GPU,
/// and Zephra's buffer is thrown away as the innocent victim. The weights are fine, so the
/// person used to press Try Again and Generate for a run the store could simply have made.
@MainActor
@Suite("A victim fault reruns the run once")
struct VictimFaultRerunTests {
    /// A store over loaded weights whose pretend GPU discards `faults` runs at step one as a
    /// victim, then works.
    private func faultingStore(_ bed: EngineTestBed, faults: Int?, victim: Bool = true) async
        -> GenerationStore
    {
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update {
            $0.deviceFaultAtStep = 1
            $0.deviceFaultIsVictim = victim
            $0.deviceFaultsLeft = faults
            $0.stepDelay = .zero
        }
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 2
        return store
    }

    @Test("one victim fault lands one picture, from the same seed, and never shows a failure")
    func oneVictimThenSuccess() async throws {
        let bed = EngineTestBed()
        let store = await faultingStore(bed, faults: 1)
        let seed = store.settings.seed
        var sawFailure = false
        store.generate()
        try await bed.waitUntil {
            if case .failed = store.state { sawFailure = true }
            return store.history.count == 1
        }
        await store.settle()
        #expect(!sawFailure, "the victim's failure must never reach the canvas")
        #expect(store.state == .ready)
        #expect(bed.control.settings.generations == 2, "the run went once more, and only once")
        #expect(bed.control.settings.lastSettings?.seed == seed, "the rerun is the same picture")
        #expect(bed.control.settings.loads == 1, "over the weights the fault left up")
        await store.shutdown()
    }

    @Test("a second victim on the same job fails with today's sentence")
    func twoVictimsFail() async throws {
        let bed = EngineTestBed()
        let store = await faultingStore(bed, faults: nil)
        store.generate()
        try await bed.waitUntil {
            if case .failed = store.state { return true }
            return false
        }
        await store.settle()
        #expect(store.state == .failed(.backend(.deviceVictim(MockBackend.deviceFaultMessage))))
        #expect(
            EngineError.backend(.deviceVictim("x")).message
                == BackendError.deviceFailed("x").errorDescription)
        #expect(bed.control.settings.generations == 2, "one rerun, never a loop")
        #expect(store.history.isEmpty)
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("a fault that is not a victim never reruns")
    func otherFaultsDoNotRerun() async throws {
        let bed = EngineTestBed()
        let store = await faultingStore(bed, faults: 1, victim: false)
        store.generate()
        await store.settle()
        #expect(store.state == .failed(.backend(.deviceFailed(MockBackend.deviceFaultMessage))))
        #expect(bed.control.settings.generations == 1)
        #expect(store.history.isEmpty)
        await store.shutdown()
    }

    @Test("a Stop during the rerun stops it and keeps nothing")
    func stopDuringTheRerun() async throws {
        let bed = EngineTestBed()
        let store = await faultingStore(bed, faults: 1)
        bed.control.update { $0.stepDelay = .milliseconds(40); $0.deviceFaultAtStep = 1 }
        store.settings.steps = 8
        store.generate()
        try await bed.waitUntil {
            bed.control.settings.generations == 2 && bed.control.settings.stepsEmitted >= 2
        }
        store.cancel()
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.history.isEmpty, "a stopped rerun keeps no picture")
        #expect(bed.control.settings.generations == 2, "and is not run a third time")
        await store.shutdown()
    }
}
