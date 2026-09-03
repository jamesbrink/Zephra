import Foundation
import MLX

/// Builds a quantized snapshot from a full-precision one, following a family's plan.
///
/// Nothing in here knows which model it is converting. The plan says which directories hold
/// weights worth packing, how finely each tensor should be squeezed, and what to copy across
/// untouched; this walks the source once, streams the result out, and writes the
/// `quantization.json` a loader needs to recognise what it is looking at.
///
/// It streams deliberately. A loader-side quantizer reads a whole component into a dictionary
/// before writing anything, which for a 24 GB float32 transformer is more memory than most Macs
/// have. This one converts a tensor at a time and spills at a byte budget, so peak memory is set
/// by the budget rather than by the model.
public enum SnapshotQuantizer {
    /// Bytes of packed tensors to hold before spilling a shard. Four gigabytes keeps the
    /// process comfortable on a 16 GB Mac while still producing shard counts a reader expects.
    public static let defaultShardBudgetBytes = 4_000_000_000

    /// Quantizes the snapshot at `source` into a new snapshot at `destination`.
    ///
    /// - Parameters:
    ///   - source: A snapshot directory laid out like the Hugging Face release.
    ///   - destination: Where to write the quantized snapshot. Created if missing; existing
    ///     files with the same names are replaced.
    ///   - plan: Which components to pack, how finely, and what to copy verbatim.
    ///   - sourceName: The repository the weights came from, recorded in the manifest.
    ///   - shardBudgetBytes: Bytes to buffer before writing a shard.
    ///   - note: Called with one line of progress at a time.
    ///   - shouldContinue: Called once before each tensor is read. Throw from it to stop the
    ///     build; the partly written component is cleared by the next run. A closure rather
    ///     than a task check because this runs from a synchronous command-line tool as well as
    ///     from the app's inference executor, and only one of them has a task to ask.
    public static func quantize(
        source: URL,
        destination: URL,
        plan: QuantizationPlan,
        sourceName: String? = nil,
        shardBudgetBytes: Int = defaultShardBudgetBytes,
        note: @escaping (String) -> Void = { _ in },
        shouldContinue: @escaping () throws -> Void = {}
    ) throws {
        let resolvedSource = source.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)
        note("quantizing \(resolvedSource.path(percentEncoded: false)): \(plan.summary)")

        var layers: [QuantizationManifest.Layer] = []
        for component in plan.components {
            layers += try ComponentQuantization(
                component: component,
                source: resolvedSource,
                destination: destination,
                shardBudgetBytes: shardBudgetBytes,
                note: note,
                shouldContinue: shouldContinue
            ).run()
            Memory.clearCache()
        }

        note("copying configs and every directory left at full precision")
        try SnapshotAncillaryFiles.copy(from: resolvedSource, to: destination, plan: plan)

        // The header reaches only the layers a name lookup misses, so it states whichever
        // precision covers the most of them. Every layer carries its own besides, which is what
        // makes a mixed build loadable at all.
        guard let fallback = QuantizationManifest.commonestPrecision(across: layers) else {
            throw QuantizationError.nothingPacked
        }
        if !plan.isUniform {
            note("mixed plan: the manifest header falls back to \(fallback.summary)")
        }
        try QuantizationManifest(
            modelId: sourceName,
            revision: nil,
            fallback: fallback,
            mode: "affine",
            layers: layers
        ).write(into: destination)
        note("wrote \(layers.count) packed layers to \(destination.path(percentEncoded: false))")
    }
}
