import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("Cancelling model downloads")
@MainActor
struct DownloadCancellationTests {
    @Test("cancel stops an initial or switched download, and a new attempt can load",
          arguments: [false, true])
    func cancelDownload(swapping: Bool) async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        if swapping { await store.bootstrap() }
        let previousLoads = bed.control.settings.loads
        bed.control.update { $0.downloadDelay = .seconds(10) }
        if swapping {
            store.switchModel(to: ModelSwitchingTests.smaller)
        } else {
            store.retry()
        }
        let downloading = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 0, totalFiles: 2, fraction: 0))
        try await bed.waitFor(store, toReach: downloading)
        #expect(store.state == downloading)
        store.cancel()
        await store.settle()
        #expect(store.state == .idle)
        #expect(!store.isSwappingModel)
        #expect(store.queue.isEmpty)
        #expect(bed.control.settings.loads == previousLoads)

        bed.control.update { $0.downloadDelay = .zero }
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == previousLoads + 1)
    }
}
