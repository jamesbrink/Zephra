import Foundation

/// Successful uploads including admission and acknowledgment overhead. Scoped to one road
/// session, so LAN measurements never promise cellular speed after reconnect.
struct InputTransferTimings {
    private var samples: [(bytes: Int, seconds: Double)] = []
    mutating func record(bytes: Int, seconds: Double) {
        guard bytes > 0, seconds.isFinite, seconds > 0 else { return }
        samples.append((bytes, seconds))
        if samples.count > 8 { samples.removeFirst() }
    }
    func estimate(bytes: Int) -> Double? {
        guard bytes >= 0 else { return nil }
        // A smaller input still pays the observed admission and acknowledgment latency.
        return samples.map { $0.seconds * max(1, Double(bytes) / Double($0.bytes)) * 1.2 }.max()
    }
}
