import Foundation
import MLX

/// Builds a quantized Z-Image snapshot from a full-precision one.
///
/// No four-bit Z-Image repository exists in the manifest format the vendored loader reads, so
/// Zephra makes its own: this walks the 33 GB bfloat16 release, packs the transformer's and the
/// text encoder's linear weights with MLX, copies the VAE and the configs across untouched, and
/// writes the `quantization.json` the loader needs to recognise the result.
///
/// The name differs from the vendored `ZImage.ZImageQuantizer` on purpose. That one loads a
/// whole component into a dictionary before it writes anything, which for a 24 GB float32
/// transformer is more memory than most Macs have; this one streams a tensor at a time.
public enum ZImageWeightQuantizer {
    /// Bytes of packed tensors to hold before spilling a shard. Four gigabytes keeps the
    /// process comfortable on a 16 GB Mac while still producing shard counts a reader expects.
    public static let defaultShardBudgetBytes = 4_000_000_000

    /// Quantizes the snapshot at `source` into a new snapshot at `destination`.
    ///
    /// - Parameters:
    ///   - source: A snapshot directory laid out like the Hugging Face release: `transformer`,
    ///     `text_encoder`, `vae`, `tokenizer`, `scheduler`, and `model_index.json`.
    ///   - destination: Where to write the quantized snapshot. Created if missing; existing
    ///     files with the same names are replaced.
    ///   - recipe: The precision to use per component.
    ///   - sourceName: The repository the weights came from, recorded in the manifest.
    ///   - shardBudgetBytes: Bytes to buffer before writing a shard.
    ///   - note: Called with one line of progress at a time.
    public static func quantize(
        source: URL,
        destination: URL,
        recipe: QuantizationRecipe,
        sourceName: String? = nil,
        shardBudgetBytes: Int = defaultShardBudgetBytes,
        note: @escaping (String) -> Void = { _ in }
    ) throws {
        let resolvedSource = source.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)
        note("quantizing \(resolvedSource.path(percentEncoded: false)) at \(recipe.summary)")

        var layers: [QuantizationManifest.Layer] = []
        for component in QuantizedComponent.allCases {
            layers += try ComponentQuantization(
                component: component,
                precision: recipe.precision(for: component),
                source: resolvedSource,
                destination: destination,
                shardBudgetBytes: shardBudgetBytes,
                note: note
            ).run()
            Memory.clearCache()
        }

        note("copying configs, tokenizer, scheduler, and the unquantized VAE")
        try SnapshotAncillaryFiles.copy(from: resolvedSource, to: destination)

        // Uniform, one precision describes the build and the header says so. Mixed, the header
        // reaches only the layers a name lookup misses, so it states whichever precision covers
        // the most of them; every layer carries its own besides.
        let fallback =
            recipe.isUniform
            ? recipe.transformer
            : QuantizationManifest.commonestPrecision(across: layers) ?? recipe.transformer
        if !recipe.isUniform {
            note("mixed recipe: the manifest header falls back to \(fallback.summary)")
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
