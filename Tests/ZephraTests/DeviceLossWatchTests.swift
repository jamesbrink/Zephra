import Foundation
import Observation
import Testing

@testable import Zephra

/// Watching for the GPU going with no window anywhere near it.
///
/// Why the watch is an object the composition root owns rather than a view's `onChange` is
/// precisely what can be shown here and not from a view: a loss that lands with the window
/// closed — a Mac left answering a paired phone — is heard whether or not that window is ever
/// opened again. The store's own `deviceLost` cannot be raised from a hosted test at all, since
/// it is set from inside `ZephraEngine`, which is why the watch reads the loss through a closure
/// and is tested against one.
@MainActor
@Suite("a device loss with no window open")
struct DeviceLossWatchTests {
    /// The loss, raised by the test and by nothing else. `fileprivate` rather than `private`
    /// because the `@Observable` macro's accessors name the type from outside the suite.
    @Observable
    fileprivate final class Latch {
        var lost: Bool
        init(lost: Bool = false) { self.lost = lost }
    }

    /// How many times the watch has reported, and no more than that.
    private final class Tally {
        var heard = 0
    }

    private func makeWatch(latch: Latch, tally: Tally) -> DeviceLossWatch {
        DeviceLossWatch(lost: { latch.lost }, heard: { tally.heard += 1 })
    }

    @Test("a loss that happened before anything started watching is heard at once")
    func aLossAlreadyStandingIsHeardOnStart() {
        let latch = Latch(lost: true)
        let tally = Tally()
        // Held in a local for the length of the test, which is what the composition root does
        // with `@State`: the watch keeps no one alive but itself, and a watch nothing holds is
        // gone before the next write.
        let watch = makeWatch(latch: latch, tally: tally)
        watch.start()
        // No turn is waited for: the first pass is synchronous, which is what carries a loss
        // that nobody was there to see.
        #expect(tally.heard == 1)
    }

    @Test("a loss with the window never opened is heard by the watch alone")
    func aLossWithNoReaderAtAllIsHeard() async {
        let latch = Latch()
        let tally = Tally()
        let watch = makeWatch(latch: latch, tally: tally)
        watch.start()
        #expect(tally.heard == 0, "nothing has gone yet")
        latch.lost = true
        #expect(
            await Self.settled { tally.heard == 1 },
            "the watch is the only reader here, and it heard")
    }

    @Test("watching twice is still one reader, so one loss is heard once")
    func startingTwiceAddsNoSecondReader() async {
        let latch = Latch()
        let tally = Tally()
        let watch = makeWatch(latch: latch, tally: tally)
        watch.start()
        // The reopened window asks again, and starts nothing new.
        watch.start()
        latch.lost = true
        #expect(await Self.settled { tally.heard == 1 })
        #expect(await Self.quiet { tally.heard == 1 }, "and nothing heard a second time")
    }

    @Test("a loss that is written again without moving is not a second loss")
    func aLossWrittenTwiceIsHeardOnce() async {
        let latch = Latch()
        let tally = Tally()
        let watch = makeWatch(latch: latch, tally: tally)
        watch.start()
        latch.lost = true
        #expect(await Self.settled { tally.heard == 1 })
        // Observation reports a write of a value that did not change, so the watch reports the
        // edge rather than the write.
        latch.lost = true
        #expect(await Self.quiet { tally.heard == 1 }, "the same loss heard only once")
    }

    @Test("a watch that never starts hears nothing")
    func anUnstartedWatchIsInert() async {
        let latch = Latch()
        let tally = Tally()
        let watch = makeWatch(latch: latch, tally: tally)
        withExtendedLifetime(watch) { latch.lost = true }
        // Nothing was started, so nothing is watching, whether or not the watch is alive.
        #expect(await Self.quiet { tally.heard == 0 })
    }

    /// Waits for the main actor to come round until `seen` holds, for up to a second.
    ///
    /// A fixed sleep would be the other option and the worse one: the watch reports on the turn
    /// after the write, and a test should wait for that turn rather than guess how long it takes.
    private static func settled(_ seen: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if seen() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return seen()
    }

    /// Holds for a hundred milliseconds and then reports whether `seen` holds throughout, which
    /// is how a test says nothing was heard: the absence is only worth asserting once enough
    /// turns have passed for a spurious report to have arrived.
    private static func quiet(_ seen: @escaping () -> Bool) async -> Bool {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(10))
            if !seen() { return false }
        }
        return seen()
    }
}
