/// The hole in a stream that `OrderedInbox` gave up waiting on and stepped over.
///
/// Three numbers is the difference between "a frame went missing" and "the stream jumped from
/// 412 to 908 with 3 frames held", which says whether frames were dropped in their hundreds or
/// one overtook its neighbours and never landed. Both ends log it at error — a skip is rare,
/// costs the phone a whole `resync`, and is the one thing to look for in `make logs` when a
/// session behaves oddly. The phone answers a gap by asking for the world again; the Mac drops
/// whatever transfer the hole was in the middle of and carries on.
public struct FrameGap: Hashable, Sendable {
    /// The counter the stream was waiting for.
    public let expected: UInt64
    /// The lowest counter that had arrived and was waiting behind the gap, where one had.
    public let nextHeld: UInt64?
    /// How many frames were waiting behind it.
    public let held: Int

    /// One gap, as the inbox found it.
    public init(expected: UInt64, nextHeld: UInt64?, held: Int) {
        self.expected = expected
        self.nextHeld = nextHeld
        self.held = held
    }

    /// How many counters the hole spans, where anything arrived past it.
    public var width: UInt64? { nextHeld.map { $0 - expected } }

    /// The gap in one line, for a log that is read long after the run it is about.
    public var summary: String {
        guard let nextHeld, let width else { return "expected \(expected), nothing past it" }
        return "expected \(expected), next held \(nextHeld), \(width) missing, \(held) waiting"
    }
}
