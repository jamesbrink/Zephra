import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore loading")
struct ModelLoadingTests {
    @Test("warm-up is skipped when the preference is off")
    func warmUpCanBeTurnedOff() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.generations == 0, "warm-up should have been skipped")
    }

    @Test("bootstrapping again once ready does nothing")
    func bootstrapIsIdempotent() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 1)
    }

    @Test("cancelling a load returns to idle, and a later bootstrap still succeeds")
    func cancelDuringLoad() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadDelay = .milliseconds(500) }
        let store = bed.store()
        let bootstrap = Task { await store.bootstrap() }
        try await bed.waitFor(store, toReach: .loading(.preparing))

        store.cancel()
        await bootstrap.value
        #expect(store.state == .idle)
        #expect(bed.control.settings.generations == 0, "warm-up should never have started")

        bed.control.update { $0.loadDelay = .zero }
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 2)
    }

    @Test("a failed load surfaces as failed, and retry recovers once the fault is cleared")
    func failedLoadThenRetry() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.loadError = .loadFailed("not enough memory") }
        let store = bed.store()
        await store.bootstrap()
        #expect(store.state == .failed(.backend(.loadFailed("not enough memory"))))

        bed.control.update { $0.loadError = nil }
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
    }
}
