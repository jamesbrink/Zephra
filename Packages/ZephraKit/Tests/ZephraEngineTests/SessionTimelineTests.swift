import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("The session timeline")
struct SessionTimelineTests {
    @Test("a place still to be filled becomes a fresh image, then an indexed one, without moving")
    func placeholderIsFilledInPlace() {
        let batch = UUID()
        let run = Fixtures.queue(batch: batch, count: 2)

        let queued = SessionTimeline.build(
            items: [], history: [], queue: [run[1]], running: run[0], isToday: { _ in true })
        #expect(queued.count == 1)
        #expect(queued[0].tiles == [.pending(0), .pending(1)])
        #expect(queued[0].isRunning)

        let image = Fixtures.image(batch: batch, at: 10, url: nil)
        let landed = SessionTimeline.build(
            items: [], history: [image], queue: [], running: run[1], isToday: { _ in true })
        #expect(landed[0].tiles == [.fresh(image), .pending(1)])

        let saved = image.withFileURL(Fixtures.url("seed-0"))
        let item = Fixtures.item(from: saved)
        let settled = SessionTimeline.build(
            items: [item], history: [saved], queue: [], running: run[1], isToday: { _ in true })
        #expect(settled[0].tiles == [.item(item), .pending(1)])
    }

    @Test("a file with no run of its own joins the neighbours it was plainly made with")
    func adjacentFilesWithoutARunAreOneRun() {
        let items = [
            Fixtures.item(prompt: "a red bicycle", at: 30),
            Fixtures.item(prompt: "a red bicycle", at: 20),
            Fixtures.item(prompt: "a green bicycle", at: 10),
        ]
        let runs = SessionTimeline.build(
            items: items, history: [], queue: [], running: nil, isToday: { _ in true })

        #expect(runs.count == 2)
        #expect(runs[0].prompt == "a red bicycle")
        #expect(runs[0].tiles.count == 2, "the two that match are one run")
        #expect(runs[1].prompt == "a green bicycle")
        #expect(runs[1].tiles.count == 1)
    }

    @Test("a file whose settings differ from its neighbour's starts a run of its own")
    func differentSettingsSplitARun() {
        let items = [
            Fixtures.item(prompt: "a red bicycle", at: 30, steps: 9),
            Fixtures.item(prompt: "a red bicycle", at: 20, steps: 4),
        ]
        let runs = SessionTimeline.build(
            items: items, history: [], queue: [], running: nil, isToday: { _ in true })

        #expect(runs.count == 2, "the same words at another step count are another run")
    }

    @Test("the run waiting sits on top, the one running under it, and the finished ones below")
    func runsAreOrderedByWhatHappensNext() {
        let finished = UUID()
        let running = Fixtures.queue(batch: UUID(), count: 1, prompt: "the harbour at night")[0]
        let waiting = Fixtures.queue(batch: UUID(), count: 1, prompt: "the same wall, no bicycle")[0]

        let runs = SessionTimeline.build(
            items: [Fixtures.item(prompt: "a red bicycle", at: 10, batch: finished)],
            history: [],
            queue: [waiting],
            running: running,
            isToday: { _ in true }
        )

        #expect(runs.map(\.prompt) == [
            "the same wall, no bicycle", "the harbour at night", "a red bicycle",
        ])
        #expect(runs[0].isWaiting && !runs[0].isRunning)
        #expect(runs[0].queuedIDs == [waiting.id], "so the whole run can be taken back out")
        #expect(runs[1].isRunning)
        #expect(!runs[2].isWaiting && !runs[2].isRunning)
    }

    @Test("the last press of Generate is on top and the one that runs next is just above the run in flight")
    func waitingRunsAreNewestFirst() {
        let running = Fixtures.queue(batch: UUID(), count: 1, prompt: "running")[0]
        let next = Fixtures.queue(batch: UUID(), count: 1, prompt: "next")[0]
        let last = Fixtures.queue(batch: UUID(), count: 1, prompt: "last")[0]

        let runs = SessionTimeline.build(
            items: [], history: [], queue: [next, last], running: running, isToday: { _ in true })

        #expect(runs.map(\.prompt) == ["last", "next", "running"])
    }

    @Test("only today's files are listed, and everything this session made whatever its date")
    func yesterdayIsTheLibrarysBusiness() {
        let today = Fixtures.item(prompt: "today", at: 10)
        let yesterday = Fixtures.item(prompt: "yesterday", at: -90_000)
        let overMidnight = Fixtures.image(batch: UUID(), at: -90_000, url: nil)

        let runs = SessionTimeline.build(
            items: [today, yesterday],
            history: [overMidnight],
            queue: [],
            running: nil,
            isToday: { $0.timeIntervalSince(Fixtures.epoch) > 0 }
        )

        #expect(runs.count == 2)
        #expect(runs.contains { $0.prompt == "today" })
        #expect(runs.contains { $0.prompt == overMidnight.settings.prompt })
        #expect(!runs.contains { $0.prompt == "yesterday" }, "the library pane shows that")
    }

    @Test("an imported picture is not a run")
    func importsAreSkipped() {
        let imported = LibraryItem(
            url: Fixtures.url("brought-in"),
            collection: .generated,
            provenance: .imported(
                SourceRecord(
                    importedAt: Fixtures.epoch, originalFileName: "photo.png",
                    width: 512, height: 512, digest: "abc")),
            fileSize: 100,
            contentModifiedAt: Fixtures.epoch
        )
        let runs = SessionTimeline.build(
            items: [imported], history: [], queue: [], running: nil, isToday: { _ in true })

        #expect(runs.isEmpty)
    }
}
