import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("Model acquisition outlives its foreground waiter")
@MainActor
struct ConcurrentDownloadTests {
    @Test("switching between blocked downloads loads only B and A completes in the background")
    func switchWithTwoDownloads() async throws {
        let bed = EngineTestBed()
        let a = BackendGate(), b = BackendGate()
        let first = ModelCatalog.default, second = ModelSwitchingTests.otherFamily
        bed.control.update { state in
            state.downloadGate = { model in await (model.id == first.id ? a : b).wait() }
        }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.retry()
        try await reached { await a.entered }
        store.switchModel(to: second)
        try await reached { await b.entered }
        await b.open()
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == second.id)
        #expect(bed.control.settings.loads == 1)
        #expect(store.downloads.items.first { $0.id == first.id }?.status == .downloading)
        await a.open()
        try await reached { store.downloads.items.first { $0.id == first.id }?.status == .completed }
        #expect(store.loadedDescriptor?.id == second.id)
        #expect(bed.control.settings.loads == 1)
        await store.shutdown()
    }

    @Test("a canceled load that ignores cancellation settles before the replacement can load")
    func noncooperativeLoad() async throws {
        let bed = EngineTestBed()
        let gate = BackendGate()
        let first = ModelCatalog.default
        bed.control.update { state in
            state.ignoresLoadCancellation = true
            state.loadGate = { model in if model.id == first.id { await gate.wait() } }
        }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.retry()
        try await reached { await gate.entered }
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        #expect(bed.control.settings.loads == 1)
        await gate.open()
        await store.settle()
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        #expect(store.state == .ready)
        #expect(bed.control.settings.unloads >= 1)
        await store.shutdown()
    }

    @Test("background failure does not fail the chosen model")
    func backgroundFailure() async throws {
        let bed = EngineTestBed()
        let gate = BackendGate()
        let first = ModelCatalog.default
        bed.control.update { state in
            state.downloadGate = { model in
                if model.id == first.id {
                    await gate.wait()
                    throw BackendError.downloadFailed("offline")
                }
            }
        }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.retry()
        try await reached { await gate.entered }
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        await store.settle()
        await gate.open()
        try await reached {
            if case .failed = store.downloads.items.first(where: { $0.id == first.id })?.status { return true }
            return false
        }
        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        await store.shutdown()
    }

    func reached(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw BackendError.loadFailed("Test barrier timed out") }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
