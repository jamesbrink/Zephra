import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the FastWan release into a loadable variant means for this family: which plan,
/// and how much of the source each component reads.
///
/// The rest of the job — the `.partial` directory, the free-space refusal, the progress bar,
/// the provenance stamp — is
/// `SnapshotBuild.pack(release:into:descriptor:plan:componentWeights:onProgress:)`'s, because
/// it is the same job whatever is being packed.
enum WanSnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar: the
    /// 10.0 GB transformer, the 11.4 GB UMT5 encoder, and the 2.8 GB autoencoder copied as it is.
    private static let componentWeights = [
        "transformer": 10.0, "text_encoder": 11.4, "vae": 2.8,
    ]

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
            plan: try WanQuantizationPlan.plan(
                bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64),
            componentWeights: componentWeights,
            onProgress: onProgress)
    }
}
