import Foundation
import Testing

@testable import ZephraLinkProtocol

/// A delta folded into the state it edits.
@Suite("A snapshot takes one delta at a time")
struct StateSnapshotApplyingTests {
    private var snapshot: StateSnapshot {
        StateSnapshot(
            hostName: "A Mac", model: LinkFixtures.model, models: [LinkFixtures.model],
            engine: EngineStateDTO(kind: .ready, acceptsGeneration: true), queue: [], running: nil,
            history: [], availability: [:], downloads: [], today: [], libraryCount: 10,
            acceptsWork: true)
    }

    @Test("the engine's state is replaced")
    func engineIsReplaced() {
        let next = snapshot.applying(
            .engine(EngineStateDTO(kind: .generating, step: 4, steps: 9, isBusy: true)))
        #expect(next.engine.kind == .generating)
        #expect(next.engine.step == 4)
    }

    @Test("a picture lands at the head of the history and never twice")
    func historyInsertsAtTheHead() {
        let id = UUID()
        let entry = HistoryEntry(id: id, fileName: "one.png", record: LinkFixtures.record)
        let once = snapshot.applying(.historyInserted(entry))
        let twice = once.applying(.historyInserted(entry))
        #expect(twice.history.count == 1)
        #expect(twice.history.first?.id == id)
        #expect(twice.applying(.historyRemoved(id)).history.isEmpty)
    }

    @Test("a library reset carries the real count, and a removal takes from it")
    func libraryCountFollowsTheFolder() {
        let reset = snapshot.applying(.library(.reset([LinkFixtures.entry], total: 4)))
        #expect(reset.libraryCount == 4)
        #expect(reset.applying(.library(.removed(["lighthouse.png"]))).libraryCount == 3)
    }

    @Test("an upsert leaves the count alone, since a change and an arrival read the same")
    func upsertLeavesTheCount() {
        #expect(snapshot.applying(.library(.upserted([LinkFixtures.entry]))).libraryCount == 10)
    }

    @Test("the count never goes below nothing")
    func countStopsAtZero() {
        let empty = snapshot.applying(.library(.reset([], total: 0)))
        #expect(empty.applying(.library(.removed(["gone.png"]))).libraryCount == 0)
    }

    @Test("the Mac saying it will not take work is one field and nothing else")
    func acceptsWorkIsOneField() {
        let next = snapshot.applying(.acceptsWork(false))
        #expect(next.acceptsWork == false)
        #expect(next.engine == snapshot.engine)
    }
}
