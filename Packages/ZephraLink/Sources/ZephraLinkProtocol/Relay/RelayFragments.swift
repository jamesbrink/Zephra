import Foundation
import Synchronization

/// The receiving half of `RelayFragment`: slices in, whole payloads out.
///
/// Slices of one message arrive **out of order**, because every `send` is a Lambda invocation of
/// its own and they post to the far end concurrently. So a set is held by its message id and
/// indexed by `i`, and the payload is released only when all `n` are there — which is what keeps
/// the sealed frame above whole, and the `OrderedInbox` above that the one place order is put
/// back.
///
/// Two bounds, because a sender that stops half way through a set must not cost this end
/// anything: a set nothing finishes is dropped after `lifetime`, and at most `setLimit` sets are
/// held at once — the oldest goes when a new one arrives over the limit. Both are checked as a
/// slice lands rather than on a clock of their own: nothing else would ask, and a set nobody is
/// adding to is a set nobody is waiting for.
public final class RelayFragments: Sendable {
    /// How long an unfinished set stands before it is dropped.
    public static let lifetime: Duration = .seconds(30)
    /// How many unfinished sets may be held at once.
    public static let setLimit = 8

    private struct Pending {
        let count: Int
        let startedAt: ContinuousClock.Instant
        var slices: [Int: Data] = [:]
    }

    private let lifetime: Duration
    private let setLimit: Int
    private let sets = Mutex<[String: Pending]>([:])

    /// A reassembler with the standard bounds, or a suite's own.
    public init(lifetime: Duration = RelayFragments.lifetime, setLimit: Int = RelayFragments.setLimit) {
        self.lifetime = lifetime
        self.setLimit = setLimit
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
        return sets.withLock { sets in
            let now = ContinuousClock.now
            sets = sets.filter { now - $0.value.startedAt < lifetime }
            var set = sets[id] ?? Pending(count: count, startedAt: now)
            // A set whose slices disagree about how many there are is not one message; the newer
            // word wins and what was held under that id goes, since one of the two is a stray.
            if set.count != count { set = Pending(count: count, startedAt: now) }
            set.slices[index] = payload
            guard set.slices.count == count else {
                sets[id] = set
                if sets.count > setLimit, let oldest = Self.oldest(in: sets, besides: id) {
                    sets.removeValue(forKey: oldest)
                }
                return nil
            }
            sets.removeValue(forKey: id)
            return (0..<count).reduce(into: Data()) { whole, index in
                whole.append(set.slices[index] ?? Data())
            }
        }
    }

    /// How many sets are part way through, which is what a suite asks about the bounds.
    public var heldSets: Int { sets.withLock { $0.count } }

    /// The set that has been waiting longest, never the one just added to.
    private static func oldest(in sets: [String: Pending], besides id: String) -> String? {
        sets.filter { $0.key != id }.min { $0.value.startedAt < $1.value.startedAt }?.key
    }
}
