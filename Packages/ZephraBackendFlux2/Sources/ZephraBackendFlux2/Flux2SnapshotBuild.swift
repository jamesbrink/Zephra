import Foundation
import ZephraCore
import ZephraQuantization

/// What packing the klein release into a loadable variant means for this family: which plan, and
/// how much of the source each component reads.
///
/// The rest of the job — the `.partial` directory, the free-space refusal, the rename — is
/// `SnapshotBuild`'s, because it is the same job whatever is being packed.
enum Flux2SnapshotBuild {
    /// Gigabytes of the release each component reads while packing, for weighting the bar: the
    /// whole 7.75 GB transformer, and the first 27 of the encoder's 36 layers plus its embedding
    /// table, 6.8 GB of its 8.04. The autoencoder is copied verbatim in a second and left out.
    private static let componentWeights = ["transformer": 7.75, "text_encoder": 6.8]

    /// Packs `release` into `destination` at `descriptor`'s precision, reporting one event per
    /// component boundary.
    static func pack(
        release: URL,
        into destination: URL,
        descriptor: ModelDescriptor,
        sourceName: String,
        onProgress: @escaping @Sendable (BuildProgressEvent) -> Void
    ) throws -> URL {
        let plan = try Flux2QuantizationPlan.plan(
            bits: descriptor.quantization == .int8 ? 8 : 4, groupSize: 64)
        var tally = BuildTally(
            components: plan.components.map(\.directoryName), weights: componentWeights)
        onProgress(tally.start)
        return try SnapshotBuild.pack(
            release: release,
            into: destination,
            plan: plan,
            sourceName: sourceName,
            freeSpaceBytes: descriptor.builtBytes,
            note: { if let event = tally.note($0) { onProgress(event) } },
            shouldContinue: { try Task.checkCancellation() }
        )
    }
}
