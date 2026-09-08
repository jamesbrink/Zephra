import Testing
import ZephraCore

@testable import Zephra

/// The Performance tab's live readout: what it reads, what it does with nothing to read, and
/// how a streamed pass is worded.
///
/// The loop's *lifetime* is SwiftUI's — a tab's `.task` is started and cancelled with the tab —
/// so what is pinned here is that it takes a reading at once and stops being asked when it is
/// cancelled, which is the half of the scope that is ours.
@Suite("the memory readout's poll")
struct MemoryReadoutTests {
    // `nonisolated`, because the stub runtime below answers from off the main actor: an
    // `InferenceRuntime` is `Sendable` and its readings are asked for wherever the caller is.
    private nonisolated static let snapshot = MemorySnapshot(
        activeBytes: 1_000_000, cacheBytes: 2_000_000, peakBytes: 3_000_000)
    private nonisolated static let pass = WeightStreamReading(bytes: 16_100_000_000, seconds: 10)

    @Test("a build with no inference runtime reads nothing at all")
    @MainActor
    func noRuntime() async {
        let poll = MemoryReadoutPoll()
        await poll.run(reading: nil)
        #expect(poll.snapshot == nil, "with nothing to ask there is nothing to show")
        #expect(poll.streamed == nil)
    }

    @Test("the first reading is taken as the loop starts, not a second later")
    @MainActor
    func firstReadingIsImmediate() async throws {
        let poll = MemoryReadoutPoll()
        let task = Task { await poll.run(reading: StubRuntime()) }
        try await Self.settle(until: { poll.snapshot != nil })
        #expect(poll.snapshot == Self.snapshot)
        #expect(poll.streamed == Self.pass)
        task.cancel()
        await task.value
    }

    @Test("cancelling the task ends the loop")
    @MainActor
    func cancellationEndsTheLoop() async throws {
        let poll = MemoryReadoutPoll()
        let task = Task { await poll.run(reading: StubRuntime()) }
        try await Self.settle(until: { poll.snapshot != nil })
        task.cancel()
        // The loop is asleep between readings; a cancelled sleep throws and the check at the
        // top of the loop is what stops it. Returning at all is the assertion.
        await task.value
    }

    @Test("the streamed row says what a pass read and how fast it read it")
    func streamedWording() {
        #expect(
            MemoryReadout.streamedText(Self.pass) == "Streamed, 16.1 GB per pass at 1.6 GB/s")
    }

    /// Turns the loop over until `condition` holds, or gives up rather than hanging the suite.
    private static func settle(until condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("the poll never took a reading")
    }

    /// A runtime with no GPU behind it that answers the two questions the readout asks.
    private struct StubRuntime: InferenceRuntime {
        func synchronize() {}
        func setCacheLimit(bytes: Int) {}
        func setMemoryLimit(bytes: Int) {}
        func deviceSummary() -> String { "stub" }
        func memorySnapshot() -> MemorySnapshot { MemoryReadoutTests.snapshot }
        func weightStreamReading() -> WeightStreamReading? { MemoryReadoutTests.pass }
        func setVAETileSize(_ tile: Int?) {}
        func vaeTileSize() -> Int? { nil }
    }
}
