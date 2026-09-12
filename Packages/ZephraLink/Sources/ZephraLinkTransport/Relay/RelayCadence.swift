import Foundation
import Synchronization

/// How fast a road may write into the relay, as a token bucket one slice at a time.
///
/// The relay is an API Gateway route and a Lambda, and the account's throttle is shared by every
/// invocation in it — both directions of every session. A 6 MB picture is about ninety-six 64 KiB
/// chunks, each sealed and cut into six slices, so nearly six hundred writes as fast as the socket
/// takes them; a 40 MB clip is four thousand. Written back to back they arrive at the throttle in
/// one burst, and what a throttle does with a burst is refuse the tail of it. A refusal is a frame
/// the far end never sees, which is a hole in its counters, which costs the whole transfer.
///
/// So a road spends tokens: `burst` of them to start, refilled at `messagesPerSecond`. The
/// allowance is allowed to go negative and the waiter sleeps off its own deficit, which is what
/// makes two writers queue behind one another rather than both reading the same "how long until a
/// token" and waking together.
public final class RelayCadence: Sendable {
    private struct State {
        /// Tokens in hand, negative while writers are queued behind the refill.
        var allowance: Double
        /// When the allowance was last brought up to date.
        var last: ContinuousClock.Instant
    }

    private let perSecond: Double
    private let capacity: Double
    private let state: Mutex<State>

    /// A bucket that refills at `messagesPerSecond` and holds at most `burst`.
    ///
    /// A cadence of zero or less paces nothing, which is what a suite that is measuring something
    /// else asks for.
    public init(messagesPerSecond: Int, burst: Int) {
        perSecond = Double(messagesPerSecond)
        capacity = Double(max(burst, 1))
        state = Mutex(State(allowance: Double(max(burst, 1)), last: ContinuousClock.now))
    }

    /// Waits until this road may write one more message. Returns at once while there are tokens.
    public func wait() async {
        guard perSecond > 0 else { return }
        let delay: Duration = state.withLock { state in
            let now = ContinuousClock.now
            state.allowance = min(capacity, state.allowance + Self.seconds(state.last, now) * perSecond)
            state.last = now
            state.allowance -= 1
            guard state.allowance < 0 else { return .zero }
            return .seconds(-state.allowance / perSecond)
        }
        guard delay > .zero else { return }
        try? await Task.sleep(for: delay)
    }

    /// How long two instants are apart, in seconds, which is the one unit the bucket counts in.
    private static func seconds(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant)
        -> Double
    {
        let span = to - from
        return Double(span.components.seconds) + Double(span.components.attoseconds) * 1e-18
    }
}
