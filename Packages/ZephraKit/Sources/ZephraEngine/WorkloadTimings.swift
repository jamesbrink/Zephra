import Foundation

/// Recent successful work only, bounded independently of the library's size.
@MainActor
public final class WorkloadTimings {
    struct Sample: Sendable {
        let key: WorkloadTimingKey
        let execution: Double
        let finalization: Double
    }
    struct Preparation {
        let model: String
        let revision: String
        let residency: String
        let seconds: Double
    }
    private var samples: [Sample] = []
    private var preparations: [Preparation] = []
    private var unloads: [(model: String, seconds: Double)] = []
    public init() {}
    public func record(_ key: WorkloadTimingKey, execution: Double, finalization: Double) {
        guard execution.isFinite, execution > 0, finalization.isFinite, finalization >= 0 else { return }
        samples.append(Sample(key: key, execution: execution, finalization: finalization))
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
    }
    public func recordPreparation(model: String, revision: String, residency: String, seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        preparations.append(Preparation(model: model, revision: revision, residency: residency, seconds: seconds))
        if preparations.count > 32 { preparations.removeFirst(preparations.count - 32) }
    }
    public func estimate(_ key: WorkloadTimingKey) -> (execution: Double, finalization: Double, samples: Int)? {
        let recent = samples.filter { $0.key == key }.suffix(8)
        guard !recent.isEmpty else { return nil }
        // An observed slow run remains in the envelope; twenty percent covers ordinary variance.
        return (recent.map(\.execution).max()! * 1.2,
                recent.map(\.finalization).max()! * 1.2, recent.count)
    }
    public func recordUnload(model: String, seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        unloads.append((model, seconds))
        if unloads.count > 32 { unloads.removeFirst() }
    }
    public func unload(model: String) -> Double? {
        unloads.filter { $0.model == model }.suffix(8).map(\.seconds).max().map { $0 * 1.2 }
    }
    public func preparation(model: String, revision: String, residency: String) -> Double? {
        preparations.filter { $0.model == model && $0.revision == revision && $0.residency == residency }
            .suffix(8).map(\.seconds).max().map { $0 * 1.2 }
    }
}
