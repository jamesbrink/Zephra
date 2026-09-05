import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

extension ModelSwapEdgeTests {
    @Test("a swap asked for during a stop keeps its flag when the stop finishes")
    func swapDuringStopKeepsItsFlag() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(150) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(bed.control.settings.loads == 1)

        // A swap begins, is stopped part-way, and another swap is asked for while the stop is
        // still settling: the new swap owns the flag from here.
        store.switchModel(to: ModelSwitchingTests.smaller)
        try await bed.waitFor(store, toReach: .loading(.preparing))
        store.cancel()
        #expect(store.isStoppingPreparation)
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        #expect(store.isSwappingModel)
        await store.stopTask?.value
        #expect(store.isSwappingModel, "the stop must not clear a flag a later swap set")

        // A retry landing in that window starts nothing of its own.
        store.retry()
        while store.isSwappingModel || store.state != .ready { await store.settle() }
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        #expect(bed.control.settings.loads == 3,
                "bootstrap, the interrupted swap, and the new one; retry added none")
        await store.shutdown()
    }
}
