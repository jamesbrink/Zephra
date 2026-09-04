import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the Qwen-Image release into a loadable variant means for this family: which
/// plan, which adapter goes into it, and how much of the source each component reads.
///
/// The precisions are exactly `make quantize-qwen`'s defaults — four bits, group 64, with the
/// modulation layers held at eight by the plan itself — because the catalog entry the app builds
/// is the one that command writes.
enum QwenImageSnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar. The
    /// transformer is 40.9 GB of the 57.7; the text encoder is 16.6, of which the vision tower
    /// and the language-modelling head the plan omits are about 2.4.
    private static let componentWeights = ["transformer": 40.9, "text_encoder": 14.2]

    /// Packs `release` into `destination` at `descriptor`'s precision, merging every adapter the
    /// descriptor names into the transformer as it goes, and reporting one event per component.
    static func pack(
        release: URL,
        into destination: URL,
        descriptor: ModelDescriptor,
        adapters: [URL],
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        let plan = try QwenImageQuantizationPlan.plan(
            bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64, adapters: adapters)
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
