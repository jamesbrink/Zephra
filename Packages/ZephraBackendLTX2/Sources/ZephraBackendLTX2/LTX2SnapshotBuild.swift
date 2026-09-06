import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the LTX-2.5 pack into a loadable variant means for this family: which plan, and
/// how much of the source each component reads.
///
/// The rest of the job — the `.partial` directory, the free-space refusal, the progress bar,
/// the provenance stamp — is
/// `SnapshotBuild.pack(release:into:descriptor:plan:componentWeights:onProgress:)`'s, because
/// it is the same job whatever is being packed.
enum LTX2SnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar: the
    /// whole 38 GB transformer file is read even though the audio half is dropped, the 6.3 GB
    /// connector likewise, the 23.8 GB encoder, and the 0.8 GB decoder copied as it is.
    private static let componentWeights = [
        "transformer": 38.0, "connector": 6.3, "text_encoder": 23.8, "vae": 0.8,
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
            plan: try LTX2QuantizationPlan.plan(
                bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64),
            componentWeights: componentWeights,
            onProgress: onProgress)
    }
}
