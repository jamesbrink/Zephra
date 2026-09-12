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
/// channel as `replayed`.
///
/// A gap nothing fills inside `hold` is loss rather than reordering — and loss is **skipped**,
/// not fatal. The release point jumps to the lowest counter waiting, the frames behind the hole
/// come out in order, and `onGap` says so once. A relay that dropped one small frame used to end
/// the session, which during a run meant a reconnection every few seconds until the phone gave
/// up; what a hole actually costs is one message, and the phone asks for the world again with
/// `Command.resync`. The one case still fatal is more than `frameLimit` frames held on one gap:
/// that is a stream nothing is going to put back together, and not memory worth keeping.
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
        /// The clock on the gap that is open right now.
        var timer: Task<Void, Never>?
        /// The counter that clock is running against, so a clock armed for a gap that has since
        /// filled cannot be the one that steps over the gap after it.
        var armedFor: UInt64?
        var onGap: (@Sendable (FrameGap, [Frame]) -> Void)?
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

    /// What to do when a gap goes unfilled, called once per skip. Set once, by whoever owns the
    /// inbox. The `FrameGap` is what the owner logs and answers — the phone asks for the world
    /// again, the Mac drops the transfer the hole was in the middle of — and the frames are what
    /// the skip released, in order, for the owner to dispatch as if they had just arrived.
    public func onGap(_ body: @escaping @Sendable (FrameGap, [Frame]) -> Void) {
        state.withLock { $0.onGap = body }
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
            state.armedFor = nil
            state.hasFailed = true
        }
    }

    /// Arms the clock against the gap that is open now, and stops it when nothing is waiting.
    ///
    /// **One clock per gap.** The hold is measured from when *this* gap opened, not from when the
    /// stream first had anything waiting: a frame arriving behind the break can fill the gap it
    /// was waiting on and leave a later one open, and a clock that kept running across that chain
    /// would step over whichever gap happened to be open when it ran out. Under sustained
    /// reordering — which is what a relay is — every gap fills in milliseconds and the stream
    /// never empties, so that clock ran out on a gap that was moments old and the frame it called
    /// lost arrived a beat later as `replayed`. The receiver was manufacturing holes with no loss
    /// underneath it at all. So the clock is re-armed whenever `next` moves.
    private func armOrDisarm() {
        let wait = holdTime
        state.withLock { state in
            guard !state.hasFailed else { return }
            guard !state.held.isEmpty else {
                state.timer?.cancel()
                state.timer = nil
                state.armedFor = nil
                return
            }
            guard state.armedFor != state.next else { return }
            state.timer?.cancel()
            let gap = state.next
            state.armedFor = gap
            state.timer = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                self?.gapRanOut(armedFor: gap)
            }
        }
    }

    /// The hold ran out with the gap still open, so the stream steps over it.
    ///
    /// The release point jumps to the lowest counter waiting and everything contiguous behind it
    /// comes out. `released(through:)` moves the channel's floor with it, which is what makes a
    /// frame the hole swallowed `replayed` rather than openable if it ever does turn up. A second
    /// hole behind the first arms the clock again.
    ///
    /// `armedFor` is the counter this clock was started against. A clock that outlived its gap —
    /// cancelled a moment too late to stop it — finds the release point has moved and does
    /// nothing, because the gap it was measuring is one somebody already filled.
    private func gapRanOut(armedFor: UInt64) {
        let skip: (gap: FrameGap, frames: [Frame], through: UInt64)? = state.withLock { state in
            guard state.armedFor == armedFor else { return nil }
            state.timer = nil
            state.armedFor = nil
            guard !state.hasFailed, let lowest = state.held.keys.min() else { return nil }
            let gap = FrameGap(expected: state.next, nextHeld: lowest, held: state.held.count)
            state.next = lowest
            var frames: [Frame] = []
            var through = lowest
            while let frame = state.held.removeValue(forKey: state.next) {
                frames.append(frame)
                through = state.next
                state.next += 1
            }
            return (gap, frames, through)
        }
        guard let skip else { return }
        channel.released(through: skip.through)
        state.withLock { $0.onGap }?(skip.gap, skip.frames)
        armOrDisarm()
    }

    /// Closes the channel and hands back the error to throw. The one way in is more frames held
    /// on one gap than the limit allows, which is the pathological case a skip cannot answer.
    @discardableResult
    private func fail() -> SecureChannelError {
        let wasOpen: Bool = state.withLock { state in
            guard !state.hasFailed else { return false }
            state.hasFailed = true
            state.timer?.cancel()
            state.timer = nil
            state.armedFor = nil
            state.held.removeAll()
            return true
        }
        guard wasOpen else { return .lost }
        channel.close()
        return .lost
    }
}
