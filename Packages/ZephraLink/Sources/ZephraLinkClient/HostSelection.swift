import Foundation
import ZephraLinkProtocol

/// Deterministic selection over fresh, host-authoritative offers; never changes the job.
public enum HostSelection {
    public static func best(_ candidates: [HostCandidate], previous: HostID? = nil) -> HostCandidate? {
        let candidates = candidates.filter(\.eligible)
        let measured = candidates.allSatisfy { $0.offer.totalSeconds != nil }
        guard let best = candidates.sorted(by: { precedes($0, $1, measured: measured) }).first else { return nil }
        if measured, let previous = candidates.first(where: { $0.id == previous }), previous.id != best.id,
           let old = previous.offer.totalSeconds, let new = best.offer.totalSeconds,
           (old + previous.pendingSeconds) - (new + best.pendingSeconds) < max(5, (old + previous.pendingSeconds) * 0.15) { return previous }
        return best
    }
    public static func reason(_ offer: HostOffer, selected: HostID? = nil, candidates: [HostCandidate] = []) -> String {
        let eligible = candidates.filter(\.eligible)
        if !eligible.isEmpty, eligible.allSatisfy({ $0.offer.totalSeconds != nil }), let selected {
            return best(eligible)?.id == selected ? "Shortest estimated wait and generation time"
                : "Keeping this Mac · estimated finish times are close"
        }
        if offer.queueCount == 0 { return offer.modelLoaded ? "Model loaded · ready now" : "Model installed · ready to load" }
        return "Best available · work will be queued"
    }
    private static func precedes(_ lhs: HostCandidate, _ rhs: HostCandidate, measured: Bool) -> Bool {
        if measured, let left = lhs.offer.totalSeconds, let right = rhs.offer.totalSeconds {
            let a = left + lhs.pendingSeconds, b = right + rhs.pendingSeconds
            if a != b { return a < b }
        }
        func tier(_ item: HostCandidate) -> Int {
            if item.offer.queueCount > 0 || item.pendingSeconds > 0 { return 2 }
            return item.offer.modelLoaded ? 0 : 1
        }
        if tier(lhs) != tier(rhs) { return tier(lhs) < tier(rhs) }
        let a = lhs.offer.queueSeconds ?? .infinity, b = rhs.offer.queueSeconds ?? .infinity
        if a != b { return a < b }
        if lhs.offer.memoryMargin != rhs.offer.memoryMargin { return lhs.offer.memoryMargin > rhs.offer.memoryMargin }
        return lhs.id < rhs.id
    }
}
