import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the Z-Image bf16 release into a loadable variant means for this family: which
/// plan, and how much of the source each component reads.
///
/// The precisions are exactly `make quantize`'s defaults — four bits, group 64 — because the
/// catalog entry the app builds is the one that command writes, and a variant that disagreed
/// with its own descriptor would be discovered an hour later. The rest of the job — the
/// `.partial` directory, the free-space refusal, the progress bar, the provenance stamp — is
/// `SnapshotBuild.pack(release:into:descriptor:plan:componentWeights:onProgress:)`'s.
enum ZImageSnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar. The
    /// transformer is three times the text encoder, so unweighted the bar would reach a half
    /// when three quarters of the bytes were done, and then crawl.
    private static let componentWeights = ["transformer": 24.6, "text_encoder": 8.05]

    /// Packs `release` into `destination` at `descriptor`'s precision.
    static func pack(
        release: URL,
        into destination: URL,
        descriptor: ModelDescriptor,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        try SnapshotBuild.pack(
            release: release,
            into: destination,
            descriptor: descriptor,
            plan: try ZImageQuantizationPlan.plan(
                bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64),
            componentWeights: componentWeights,
            onProgress: onProgress)
    }
}
