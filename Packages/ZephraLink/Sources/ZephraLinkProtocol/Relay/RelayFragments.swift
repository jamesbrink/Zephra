import Foundation
import Synchronization
import os

/// The receiving half of `RelayFragment`: slices in, whole payloads out.
///
/// Slices of one message arrive **out of order**, because every `send` is a Lambda invocation of
/// its own and they post to the far end concurrently. So a set is held by its message id and
/// indexed by `i`, and the payload is released only when all `n` are there — which is what keeps
/// the sealed frame above whole, and the `OrderedInbox` above that the one place order is put
/// back.
///
/// Slices of *different* messages interleave for the same reason, and that is what the bounds are
/// really about: a 64 KiB blob chunk is six slices, several chunks are in flight at once, and a
/// live picture transfer had far more than eight `m` sets open together. The old cap of eight
/// evicted the oldest set on every new one, and sixteen frames vanished in a burst while the
/// relay logged every one of them forwarded. So the cap is `setLimit` (256) sets, expiry is tried
/// first — a set nothing finishes goes after `lifetime` (30 s) — and only past the cap does the
/// oldest go to make room. **Every eviction is logged**, so a set dropped part way through is
/// never silent again.
///
/// What that costs: a set holds at most `RelayFragment.sliceLimit` (88) slices of
/// `RelayFragment.byteLimit` (18,000) bytes, so 256 *maximal* sets would be about 400 MB — a
/// worst case real traffic never reaches, since a blob chunk is six slices, roughly 108 KB a set.
/// A count is not a memory bound either way, so `byteLimit` (64 MiB) held across all sets is the
/// real guard: past it the oldest set goes, logged, whatever the count says.
public final class RelayFragments: Sendable {
    /// How long an unfinished set stands before it is dropped.
    public static let lifetime: Duration = .seconds(30)
    /// How many unfinished sets may be held at once.
    public static let setLimit = 256
    /// How many bytes of held slices there may be across every set at once.
    public static let byteLimit = 64 * 1024 * 1024

    /// Why a set was dropped before anything finished it, as the log spells it.
    enum Eviction: String {
        case expired
        case setLimit = "set-limit"
        case byteLimit = "byte-limit"
    }

    /// One message's slices, and what they weigh.
    struct Pending {
        let count: Int
        let startedAt: ContinuousClock.Instant
        var slices: [Int: Data] = [:]
        var bytes = 0
    }

    private let lifetime: Duration
    private let setLimit: Int
    private let byteLimit: Int
    private let state = Mutex(PendingSets())
    private let logger = Logger(subsystem: "io.zephra", category: "link.relay")

    /// A reassembler with the standard bounds, or a suite's own.
    public init(
        lifetime: Duration = RelayFragments.lifetime,
        setLimit: Int = RelayFragments.setLimit,
        byteLimit: Int = RelayFragments.byteLimit
    ) {
        self.lifetime = lifetime
        self.setLimit = setLimit
        self.byteLimit = byteLimit
    }

    /// One `send` off the socket, as the whole payload it completes or nil while it does not.
    ///
    /// A `send` with no `m` is not a fragment and passes straight through, which is every frame
    /// a previous build sent and every small one this build sends.
    public func accept(_ message: RelayMessage) -> Data? {
        guard case .send(let payload, let id, let index, let count) = message else { return nil }
        guard let id, let index, let count else { return payload }
        guard count > 0, count <= RelayFragment.sliceLimit, index >= 0, index < count else {
            return nil
        }
        var evicted: [(id: String, set: Pending, why: Eviction)] = []
        let whole = state.withLock { sets -> Data? in
            let now = ContinuousClock.now
            sets.expire(olderThan: lifetime, at: now, into: &evicted)
            // A set whose slices disagree about how many there are is not one message; the newer
            // word wins and what was held under that id goes, since one of the two is a stray.
            var set = sets.remove(id) ?? Pending(count: count, startedAt: now)
            if set.count != count { set = Pending(count: count, startedAt: now) }
            set.bytes += payload.count - (set.slices[index]?.count ?? 0)
            set.slices[index] = payload
            guard set.slices.count == count else {
                sets.insert(set, as: id)
                sets.trim(to: setLimit, bytes: byteLimit, keeping: id, into: &evicted)
                return nil
            }
            return (0..<count).reduce(into: Data()) { whole, index in
                whole.append(set.slices[index] ?? Data())
            }
        }
        for drop in evicted { log(drop.id, drop.set, drop.why) }
        return whole
    }

    /// How many sets are part way through, which is what a suite asks about the bounds.
    public var heldSets: Int { state.withLock { $0.sets.count } }

    /// How many bytes of slices are held across every unfinished set.
    public var heldBytes: Int { state.withLock { $0.bytes } }

    /// An eviction, with enough of the set to say which message lost frames and how far it got.
    private func log(_ id: String, _ set: Pending, _ why: Eviction) {
        let age = ContinuousClock.now - set.startedAt
        logger.info(
            """
            relay fragment set dropped: reason=\(why.rawValue, privacy: .public) \
            m=\(id, privacy: .public) had=\(set.slices.count, privacy: .public) \
            of n=\(set.count, privacy: .public) age=\(age.wholeMilliseconds, privacy: .public)ms
            """)
    }
}
