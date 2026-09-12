import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What a phone is told about queueing behind the picture the Mac is rendering.
///
/// `EngineState` alone cannot answer it — a state of `.generating` says a run is in flight and
/// nothing about whether another may join the queue behind it — so the store stamps it and both
/// projection sites go through `EngineStateProjection`. Two tests, one per site: the snapshot a
/// session opens with, and the delta a session already open is sent.
extension CompanionHostTests {
    @Test("a phone that connects mid-run is told it may still queue one")
    func theSnapshotSaysAnotherMayBeQueued() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update { $0.stepDelay = .milliseconds(20) }
        await bed.bootstrap()
        bed.store.settings.prompt = "a lighthouse"
        bed.store.settings.steps = 8
        bed.store.generate()
        try await bed.engine.waitForStep()

        let phone = try await bed.pairedPhone()
        let snapshot = try await phone.snapshot()

        #expect(snapshot.engine.kind == .generating)
        #expect(!snapshot.engine.acceptsGeneration, "the engine is not idle")
        #expect(snapshot.engine.canQueue, "and it will still take one behind this")
        #expect(snapshot.acceptsWork, "a run closes none of the Mac's gates")

        bed.store.cancel()
        await bed.shutdown()
    }

    @Test("a run starting is published as a state another may be queued behind")
    func theDeltaSaysAnotherMayBeQueued() async throws {
        let bed = CompanionTestBed()
        bed.engine.control.update { $0.stepDelay = .milliseconds(20) }
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        var state = try await phone.snapshot()
        #expect(state.engine.canQueue, "an idle Mac, before anything runs")

        bed.store.settings.prompt = "a lighthouse"
        bed.store.settings.steps = 8
        bed.store.generate()

        let engine = try await phone.waitFor { () -> EngineStateDTO? in
            for delta in (try? phone.deltas()) ?? [] { state = state.applying(delta) }
            return state.engine.kind == .generating ? state.engine : nil
        }
        #expect(engine.canQueue, "which is what keeps Generate alive on the phone")

        bed.store.cancel()
        await bed.shutdown()
    }
}
