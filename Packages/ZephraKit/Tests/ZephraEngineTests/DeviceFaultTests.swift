import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// What a GPU fault costs.
///
/// Another process faults the device, the driver recovers it, and this process's command
/// buffer comes back discarded. The runtime raises that on the thread the work was asked on,
/// and with no boundary around it the process ends. With one, the run is lost and nothing else
/// is: the weights stay up, the queue empties, and the next press works.
@MainActor
@Suite("A GPU fault mid-run")
struct DeviceFaultTests {
    @Test("a device fault fails the run, keeps no picture, and empties the queue")
    func deviceFaultFailsTheRun() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.state == .ready)

        bed.control.update { $0.deviceFaultAtStep = 1; $0.stepDelay = .zero }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()

        #expect(
            store.state == .failed(.backend(.deviceFailed(MockBackend.deviceFaultMessage))),
            "a fault must not read as a stop")
        #expect(store.history.isEmpty, "a run the GPU lost keeps nothing")
        #expect(store.queue.isEmpty)
        #expect(try bed.writtenFiles().isEmpty)
        await store.shutdown()
    }

    @Test("a device fault leaves the weights up, so retry generates without reloading")
    func deviceFaultThenRetrySucceeds() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let loadsBefore = bed.control.settings.loads

        bed.control.update { $0.deviceFaultAtStep = 1; $0.stepDelay = .zero }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()
        #expect(store.state == .failed(.backend(.deviceFailed(MockBackend.deviceFaultMessage))))
        #expect(store.loadedDescriptor != nil, "the device recovers; the weights do not move")

        // The device came back, which is what Try Again is for. Only the mock's fault is put
        // away: the fault itself went out with the boundary that caught it, so a retry that
        // failed here would be a box outliving its run.
        bed.control.update { $0.deviceFaultAtStep = nil }
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == loadsBefore, "retry reloaded a resident model")

        store.generate()
        await store.settle()
        #expect(store.history.count == 1)
        #expect(store.state == .ready)
        await store.shutdown()
    }

    @Test("a device fault while the weights are read unloads them and says the GPU stopped")
    func deviceFaultDuringLoadUnloads() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.deviceFaultDuringLoad = true }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        #expect(store.state == .failed(.backend(.deviceFailed(MockBackend.deviceFaultMessage))))
        #expect(bed.control.settings.unloads == 1, "a half-read model must not be left holding")
        #expect(store.loadedDescriptor == nil)
        await store.shutdown()
    }
}
