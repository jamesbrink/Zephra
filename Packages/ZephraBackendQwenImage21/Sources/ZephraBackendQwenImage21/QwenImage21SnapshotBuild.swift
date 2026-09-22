import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the Qwen-Image 2.1 release into a loadable variant means for this family: which
/// plan, and how much of the source each component reads.
///
/// The rest of the job — the `.partial` directory, the free-space refusal, the progress bar,
/// the provenance stamp — is
/// `SnapshotBuild.pack(release:into:descriptor:plan:componentWeights:onProgress:)`'s, because
/// it is the same job whatever is being packed.
enum QwenImage21SnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar.
    /// Measured off the release's own shards: the transformer's two are 14.23 GB, and the
    /// encoder's four are 17.53 GB less the 1.25 GB `lm_head.weight` the plan omits, which
    /// nothing in this port ever loads. The 1.35 GB autoencoder is copied verbatim in a moment
    /// and left out, as the tokenizer and the scheduler are.
    private static let componentWeights = ["transformer": 14.2, "text_encoder": 16.3]

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
            plan: try QwenImage21QuantizationPlan.plan(
                bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64),
            componentWeights: componentWeights,
            onProgress: onProgress)
    }
}
