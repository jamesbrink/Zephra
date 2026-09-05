import Foundation
import Testing
import ZephraCore

@testable import ZephraSnapshot

@Suite("The download tally's rate")
struct DownloadTallyTests {
    @Test("a partial the server would not resume never reports a negative rate")
    func discardNeverGoesNegative() {
        var tally = DownloadTally(totalFiles: 1, totalBytes: 10_000)
        let start = ContinuousClock.now
        // Four thousand bytes were on disk before the transfer began.
        tally.advance(by: 4_000)
        _ = tally.report(force: true, now: start)
        // The server answered 200: those bytes are at the wrong offset and are thrown away.
        tally.discard(4_000)
        let event = tally.report(force: true, now: start + .seconds(1))

        #expect(event?.completedBytes == 0)
        #expect(event.map { $0.bytesPerSecond ?? 0 } ?? 0 >= 0, "never below zero")
    }

    @Test("the rate after a discard measures what arrived since, not what was thrown away")
    func rateAfterDiscardCountsNewBytes() {
        var tally = DownloadTally(totalFiles: 1, totalBytes: 10_000)
        let start = ContinuousClock.now
        tally.advance(by: 4_000)
        _ = tally.report(force: true, now: start)
        tally.discard(4_000)
        tally.advance(by: 2_000)
        let event = tally.report(force: true, now: start + .seconds(1))

        #expect(event?.completedBytes == 2_000)
        #expect(event?.bytesPerSecond.map { abs($0 - 2_000) < 1 } == true)
    }
}
