import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

extension ConcurrentDownloadTests {
    @Test("shutdown awaits noncooperative preparation and closes new work admission")
    func shutdownWaits() async throws {
        let bed = EngineTestBed()
        let gate = BackendGate()
        bed.control.update { state in state.downloadGate = { _ in await gate.wait() } }
        let store = bed.store()
        store.retry()
        try await reached { await gate.entered }
        let stopping = Task { await store.shutdown() }
        try await reached { store.isShuttingDown }
        let before = store.descriptor
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        store.retry()
        #expect(store.descriptor == before)
        await gate.open()
        await stopping.value
        #expect(store.loadedDescriptor == nil)
        #expect(store.downloads.retained.isEmpty)
        #expect(bed.control.settings.loads == 0)
    }

    @Test("pause settles without auto-restarting, and resume can prepare the selected model")
    func pauseAndResume() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.downloadDelay = .seconds(10) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.retry()
        try await reached { store.downloads.items.first?.status == .downloading }
        store.pauseDownload(store.descriptor.id)
        await store.settle()
        #expect(store.state == .idle)
        #expect(store.downloads.items.first?.status == .paused)
        await store.refreshAvailability()
        #expect(store.state == .idle)
        bed.control.update { $0.downloadDelay = .zero }
        store.resumeDownload(store.descriptor)
        await store.settle()
        #expect(store.state == .ready)
        await store.shutdown()
    }

    @Test("folder changes pause every background request before changing the root")
    func folderChangeStopsBackgrounds() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.downloadDelay = .seconds(10) }
        let store = bed.store()
        store.retry()
        try await reached { store.downloads.items.count == 1 }
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        try await reached { store.downloads.items.count == 2 }
        let destination = ModelLocations(root: bed.directory.appending(path: "new-models"))
        _ = try await store.changeModelDirectory(to: destination)
        #expect(store.downloads.retained.isEmpty)
        #expect(store.modelLocations == destination)
        #expect(store.state == .idle)
        #expect(store.downloads.items.allSatisfy { $0.status == .paused })
    }
}
