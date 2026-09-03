import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("The wall's blocks")
struct TimelineBlockTests {
    @Test("singles share a block, a batch stands alone, and waiting runs are not on the wall")
    func singlesShareAndBatchesStandAlone() {
        let batch = UUID()
        let items = [
            Fixtures.item(prompt: "a tram", at: 50),
            Fixtures.item(prompt: "a harbour", at: 40),
            Fixtures.item(prompt: "a bicycle", at: 30, batch: batch),
            Fixtures.item(prompt: "a bicycle", at: 20, batch: batch),
            Fixtures.item(prompt: "a greenhouse", at: 10),
        ]
        let waiting = Fixtures.queue(batch: UUID(), count: 2, prompt: "later")
        let runs = SessionTimeline.build(
            items: items, history: [], queue: waiting, running: nil, isToday: { _ in true })
        let blocks = SessionTimeline.blocks(of: runs)

        #expect(blocks.map { $0.tiles.count } == [2, 2, 1])
        #expect(blocks[0].tiles == [.item(items[0]), .item(items[1])])
        #expect(blocks[1].id == batch)
        #expect(blocks[1].tiles == [.item(items[3]), .item(items[2])])
        #expect(blocks[2].tiles == [.item(items[4])])
    }

    @Test("the running run leads on its own, dashed places and all, even as a run of one")
    func runningRunLeads() {
        let batch = UUID()
        let run = Fixtures.queue(batch: batch, count: 1)
        let older = Fixtures.item(prompt: "a harbour", at: 10)
        let runs = SessionTimeline.build(
            items: [older], history: [], queue: [], running: run[0], isToday: { _ in true })
        let blocks = SessionTimeline.blocks(of: runs)

        #expect(blocks.map(\.id) == [batch, runs[1].id])
        #expect(blocks[0].tiles == [.pending(0)])
    }

    @Test("a shared block keeps its id as singles join it")
    func sharedBlockKeepsItsID() {
        let first = Fixtures.item(prompt: "a tram", at: 20)
        let before = SessionTimeline.blocks(of: SessionTimeline.build(
            items: [first], history: [], queue: [], running: nil, isToday: { _ in true }))
        let second = Fixtures.item(prompt: "a harbour", at: 30)
        let after = SessionTimeline.blocks(of: SessionTimeline.build(
            items: [second, first], history: [], queue: [], running: nil, isToday: { _ in true }))

        #expect(before.count == 1 && after.count == 1)
        #expect(after[0].tiles.count == 2)
        // The block is named for its newest run, so it changes name when a newer single joins
        // at the top and keeps it when the wall is merely redrawn.
        #expect(after[0].id != before[0].id)
        let redrawn = SessionTimeline.blocks(of: SessionTimeline.build(
            items: [second, first], history: [], queue: [], running: nil, isToday: { _ in true }))
        #expect(redrawn[0].id == after[0].id)
    }
}
