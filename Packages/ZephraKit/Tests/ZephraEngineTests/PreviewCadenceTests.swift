import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The Live preview setting reaching the backend as the run's task-local, and a warm-up
/// showing no frames whatever it says.
@MainActor
@Suite("The live preview cadence")
struct PreviewCadenceTests {
    @Test("a run's backend sees the store's cadence, and the warm-up sees off")
    func theBackendSeesTheStoresCadence() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.previewCadence = .everyStep
        await store.bootstrap()
        #expect(bed.control.settings.cadences == [.off], "the warm-up makes no frames")

        bed.control.update { $0.stepDelay = .zero }
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 2
        store.generate()
        await store.settle()
        #expect(bed.control.settings.cadences == [.off, .everyStep])

        store.previewCadence = .off
        store.generate()
        await store.settle()
        #expect(bed.control.settings.cadences.last == .off, "a change applies to the next run")
        await store.shutdown()
    }

    @Test("a store nobody told keeps today's balanced frames")
    func theDefaultIsBalanced() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .zero }
        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()
        #expect(bed.control.settings.cadences == [.balanced])
        await store.shutdown()
    }
}
