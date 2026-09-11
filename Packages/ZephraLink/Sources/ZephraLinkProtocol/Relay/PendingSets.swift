import Foundation

/// The sets `RelayFragments` is holding, and the two bounds over them, with the bytes counted as
/// slices land rather than summed over every set on every frame.
///
/// A set is only ever dropped here through `evict`, so nothing leaves without the caller being
/// handed what to log about it.
struct PendingSets {
    private(set) var sets: [String: RelayFragments.Pending] = [:]
    /// What every held set weighs together, the guard the count alone is not.
    private(set) var bytes = 0

    typealias Drop = (id: String, set: RelayFragments.Pending, why: RelayFragments.Eviction)

    /// The set held under an id, taken out so a caller can add to it and put it back.
    mutating func remove(_ id: String) -> RelayFragments.Pending? {
        guard let set = sets.removeValue(forKey: id) else { return nil }
        bytes -= set.bytes
        return set
    }

    mutating func insert(_ set: RelayFragments.Pending, as id: String) {
        if let old = sets.updateValue(set, forKey: id) { bytes -= old.bytes }
        bytes += set.bytes
    }

    /// Every set nothing has finished within `lifetime`, which is the first thing tried and the
    /// only eviction that is nobody's loss: the sender stopped part way through.
    mutating func expire(olderThan lifetime: Duration, at now: ContinuousClock.Instant, into drops: inout [Drop]) {
        for (id, set) in sets where now - set.startedAt >= lifetime {
            evict(id, .expired, into: &drops)
        }
    }

    /// The oldest sets, until both bounds hold again. `keeping` is the set the slice that just
    /// landed belongs to, which is never the one dropped to make room for itself.
    mutating func trim(to setLimit: Int, bytes byteLimit: Int, keeping id: String, into drops: inout [Drop]) {
        while sets.count > setLimit || bytes > byteLimit {
            guard let oldest = oldest(besides: id) else { return }
            evict(oldest, sets.count > setLimit ? .setLimit : .byteLimit, into: &drops)
        }
    }

    private mutating func evict(_ id: String, _ why: RelayFragments.Eviction, into drops: inout [Drop]) {
        guard let set = remove(id) else { return }
        drops.append((id, set, why))
    }

    /// The set that has been waiting longest, never the one just added to.
    private func oldest(besides id: String) -> String? {
        sets.filter { $0.key != id }.min { $0.value.startedAt < $1.value.startedAt }?.key
    }
}

extension Duration {
    /// The span as whole milliseconds, which is how long a dropped set had been waiting.
    var wholeMilliseconds: Int64 {
        let parts = components
        return parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
    }
}
