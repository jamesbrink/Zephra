import Foundation
import ZephraCore
import ZephraSnapshot

extension SnapshotBuild {
    /// Packs `release` into `destination` as the variant `descriptor` names: checked for the
    /// space `builtBytes` says it needs, stoppable between tensors by task cancellation,
    /// reported one event per component boundary, and stamped with the descriptor's provenance
    /// so the app accepts the result as its own.
    ///
    /// Every family's build is this call with its own `plan` and `componentWeights`; the rest
    /// of the job was three copies of the same eight lines before it was one.
    ///
    /// - Parameters:
    ///   - plan: Which directories to pack and how finely, from the family's own plan.
    ///   - componentWeights: Gigabytes of the release each component reads, by directory
    ///     name, for weighting the progress bar; see `BuildTally`.
    public static func pack(
        release: URL,
        into destination: URL,
        descriptor: ModelDescriptor,
        plan: QuantizationPlan,
        componentWeights: [String: Double],
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        var tally = BuildTally(
            components: plan.components.map(\.directoryName), weights: componentWeights)
        onProgress(tally.start)
        return try pack(
            release: release,
            into: destination,
            plan: plan,
            sourceName: descriptor.sourceName,
            freeSpaceBytes: descriptor.builtBytes,
            note: { if let event = tally.note($0) { onProgress(event) } },
            shouldContinue: { try Task.checkCancellation() },
            finalize: { try PackedProvenance.write(descriptor, into: $0) }
        )
    }
}
