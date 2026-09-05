import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Stopping during the decode")
struct GenerationStopTests {
    @Test("a stop that lands after the last step publishes nothing and writes nothing")
    func stopAfterLastStepKeepsNoImage() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update {
            $0.stepDelay = .milliseconds(5)
            $0.ignoresFinalCancellation = true
            $0.decodeDelay = .milliseconds(300)
        }
        store.settings.prompt = "x"
        store.settings.steps = 2
        store.generate()
        try await bed.waitForStep(beyond: 1)
        try await Task.sleep(for: .milliseconds(50))
        store.cancel()
        #expect(store.state == .cancelling)
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.history.isEmpty, "a stopped run keeps no image")
        #expect(store.current == nil)
        #expect(try bed.writtenFiles().isEmpty)
        await store.shutdown()
    }

    @Test("an image that finishes carries the batch it was queued in even if cancel emptied the queue a moment later")
    func finishedImageKeepsItsBatch() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(5) }
        store.settings.prompt = "x"
        store.settings.steps = 2
        store.generate(count: 2)
        let batch = try #require(store.queue.first?.batchID)
        try await bed.waitUntil { store.history.count == 1 }
        store.cancel()
        await store.settle()

        #expect(store.history.count == 1, "the second seed was stopped")
        #expect(store.history[0].batchID == batch)
        #expect(store.history[0].modelID == ModelCatalog.default.id)
        await store.shutdown()
    }
}
