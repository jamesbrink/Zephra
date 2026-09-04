import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the Z-Image bf16 release into a loadable variant means for this family: which
/// plan, and how much of the source each component reads.
///
/// The precisions are exactly `make quantize`'s defaults — four bits, group 64 — because the
/// catalog entry the app builds is the one that command writes, and a variant that disagreed
/// with its own descriptor would be discovered an hour later.
enum ZImageSnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar. The
    /// transformer is three times the text encoder, so without this the bar would sit at three
    /// quarters for most of the build.
    private static let componentWeights = ["transformer": 24.6, "text_encoder": 8.05]

    /// Packs `release` into `destination` at `descriptor`'s precision, reporting one event per
    /// component boundary.
    static func pack(
        release: URL,
        into destination: URL,
        descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        let plan = try ZImageQuantizationPlan.plan(
            bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64)
        var tally = BuildTally(
            components: plan.components.map(\.directoryName), weights: componentWeights)
        onProgress(tally.start)
        return try SnapshotBuild.pack(
            release: release,
            into: destination,
            plan: plan,
            sourceName: descriptor.sourceName,
            freeSpaceBytes: descriptor.builtBytes,
            note: { if let event = tally.note($0) { onProgress(event) } },
            shouldContinue: { try Task.checkCancellation() }
        )
    }
}
