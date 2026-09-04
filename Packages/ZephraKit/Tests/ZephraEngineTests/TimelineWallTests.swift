import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("The wall")
struct TimelineWallTests {
    @Test("the wall is one flow: batches and singles in run order, waiting runs left off")
    func oneFlowInRunOrder() {
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

        #expect(SessionTimeline.wall(of: runs) == [
            .item(items[0]), .item(items[1]), .item(items[3]), .item(items[2]), .item(items[4]),
        ])
    }

    @Test("the running run's dashed places lead the wall")
    func runningRunLeads() {
        let run = Fixtures.queue(batch: UUID(), count: 1)
        let older = Fixtures.item(prompt: "a harbour", at: 10)
        let runs = SessionTimeline.build(
            items: [older], history: [], queue: [], running: run[0], isToday: { _ in true })

        #expect(SessionTimeline.wall(of: runs) == [.pending(0), .item(older)])
    }
}
