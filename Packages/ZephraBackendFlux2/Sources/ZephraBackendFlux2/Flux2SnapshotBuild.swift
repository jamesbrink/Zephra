import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the klein release into a loadable variant means for this family: which plan, and
/// how much of the source each component reads.
///
/// The rest of the job — the `.partial` directory, the free-space refusal, the progress bar,
/// the provenance stamp — is
/// `SnapshotBuild.pack(release:into:descriptor:plan:componentWeights:onProgress:)`'s, because
/// it is the same job whatever is being packed.
enum Flux2SnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar: the
    /// whole 7.75 GB transformer, and the first 27 of the encoder's 36 layers plus its embedding
    /// table, 6.8 GB of its 8.04. The autoencoder is copied verbatim in a second and left out.
    private static let componentWeights = ["transformer": 7.75, "text_encoder": 6.8]

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
            plan: try Flux2QuantizationPlan.plan(
                bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64),
            componentWeights: componentWeights,
            onProgress: onProgress)
    }
}
