import Foundation
import Synchronization

/// The receiving half of a channel, in the order the sender sealed things in.
///
/// A road does not promise order any more. Each hop is TCP under a WebSocket, but the relay is
/// two hops with a Lambda between them: every `send` is an invocation of its own, and under a
/// sustained stream — a delta every fifty milliseconds while a run goes — those invocations post
/// to the far end concurrently and frames arrive overtaken. Everything above this expects one
/// ordered stream: `BlobReassembly` takes chunks in order only, and a `StateDelta` applied out of
/// order leaves the phone showing a step count that went backwards.
///
/// So frames are opened as they arrive and released in counter order. One that overtook its
/// neighbours waits here until the frames before it land, at most `frameLimit` of them and no
/// longer than `hold`. A frame that arrives after the stream moved past it is dropped by the
/// channel as `replayed`. A gap nothing fills inside `hold` is loss rather than reordering, and
/// loss means the stream is not whole: the channel is closed and whoever owns the inbox is told.
public final class OrderedInbox: Sendable {
    /// How long a gap may stand before it is loss. Two orders of magnitude more than a relay's
    /// own spread, and a fraction of what a person would call a stall.
    public static let hold: Duration = .milliseconds(500)
    /// How many frames may wait on one gap. A run sends twenty a second, so this is more than ten
    /// seconds of stream, and not memory worth keeping for a sender that will never catch up.
    public static let frameLimit = 256

    private struct State {
        /// The frames that arrived early, by the counter each carries.
        var held: [UInt64: Frame] = [:]
        /// The counter the next frame to be released will carry.
        var next: UInt64 = 0
        /// The clock on the gap that is open right now, armed when it opened and not since.
        var timer: Task<Void, Never>?
        var onLoss: (@Sendable (FrameGap) -> Void)?
        var hasFailed = false
    }

    private let channel: SecureChannel
    private let holdTime: Duration
    private let frameLimit: Int
    private let state = Mutex(State())

    /// An inbox over one channel. The hold and the limit are arguments so a suite can ask the
    /// question in milliseconds rather than waiting half a second on every gap.
    public init(
        channel: SecureChannel,
        hold: Duration = OrderedInbox.hold,
        frameLimit: Int = OrderedInbox.frameLimit
    ) {
        self.channel = channel
        self.holdTime = hold
        self.frameLimit = frameLimit
    }

    /// What to do when a gap goes unfilled. Set once, by whoever owns the inbox; the channel is
    /// already closed by the time it runs, so this is about the session and not the stream. The
    /// `FrameGap` is what the owner logs: which counter never came, and what was waiting on it.
    public func onLoss(_ body: @escaping @Sendable (FrameGap) -> Void) {
        state.withLock { $0.onLoss = body }
    }

    /// One frame off the road, and everything it makes ready, oldest first.
    ///
    /// Usually one frame in and one frame out. A frame that overtook its neighbours gives back
    /// nothing until they land, and the one that fills the gap gives back the whole run at once.
    public func accept(_ data: Data) throws -> [Frame] {
        let opened = try channel.open(data)
        var ready: [Frame] = []
        var releasedThrough: UInt64?
        let isOverfull: Bool = state.withLock { state in
            // The channel refuses anything below its own floor, which is this counter; the guard
            // is what keeps the two from ever disagreeing silently.
            guard opened.counter >= state.next else { return false }
            state.held[opened.counter] = opened.frame
            while let frame = state.held.removeValue(forKey: state.next) {
                ready.append(frame)
                releasedThrough = state.next
                state.next += 1
            }
            return state.held.count > frameLimit
        }
        if let releasedThrough { channel.released(through: releasedThrough) }
        guard !isOverfull else { throw fail() }
        armOrDisarm()
        return ready
    }

    /// Stops the clock. The session is going down and a gap it was holding is nobody's problem.
    public func stop() {
        state.withLock { state in
            state.timer?.cancel()
            state.timer = nil
            state.hasFailed = true
        }
    }

    /// Arms the clock when a gap is open and nothing is timing it, and stops it when the gap has
    /// filled. Armed once per gap and never restarted by a later frame: the hold is measured from
    /// when the stream broke, not from the last thing that arrived behind the break.
    private func armOrDisarm() {
        let wait = holdTime
        state.withLock { state in
            guard !state.hasFailed else { return }
            guard !state.held.isEmpty else {
                state.timer?.cancel()
                state.timer = nil
                return
            }
            guard state.timer == nil else { return }
            state.timer = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                self?.gapRanOut()
            }
        }
    }

    /// The hold ran out with the gap still open.
    private func gapRanOut() {
        let stillOpen: Bool = state.withLock { state in
            state.timer = nil
            return !state.held.isEmpty && !state.hasFailed
        }
        guard stillOpen else { return }
        fail()
    }

    /// Closes the channel, tells the owner, and hands back the error to throw where there is a
    /// caller to throw it at.
    @discardableResult
    private func fail() -> SecureChannelError {
        let notify: (gap: FrameGap?, body: (@Sendable (FrameGap) -> Void)?) = state.withLock {
            state in
            guard !state.hasFailed else { return (nil, nil) }
            state.hasFailed = true
            state.timer?.cancel()
            state.timer = nil
            let gap = FrameGap(
                expected: state.next, nextHeld: state.held.keys.min(), held: state.held.count)
            state.held.removeAll()
            return (gap, state.onLoss)
        }
        guard let gap = notify.gap else { return .lost }
        channel.close()
        notify.body?(gap)
        return .lost
    }
}
