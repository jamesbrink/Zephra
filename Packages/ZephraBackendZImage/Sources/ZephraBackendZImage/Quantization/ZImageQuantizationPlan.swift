import Foundation
import ZephraQuantization

/// How a Z-Image snapshot is packed: which directories hold weights, which tensors are left
/// alone, and what the rest is squeezed to.
///
/// The rule set is copied from the export that produced `mzbac/Z-Image-Turbo-8bit`, and it has
/// to stay copied from it. The vendored loader decides what was quantized by looking for a
/// matching `.scales` key, so packing a tensor the reference build left alone stops the module
/// tree matching the weights — a failure that shows up as a model that loads and then paints
/// colour blobs, not as an error.
public enum ZImageQuantizationPlan {
    /// Directories carried across whole. The VAE is among them: it is a fifth of a gigabyte and
    /// packing it costs visible artefacts for no real saving.
    static let verbatimDirectories = ["tokenizer", "scheduler", "vae"]

    /// The two submodules the loader restores by hand rather than through the module tree, so
    /// nothing inside them may be packed.
    static let dictionaryModules: [WeightPrecisionRule] = [
        WeightPrecisionRule(.prefix("all_x_embedder"), precision: nil),
        WeightPrecisionRule(.prefix("all_final_layer"), precision: nil),
    ]

    /// A plan packing the transformer and the text encoder at the given precisions.
    ///
    /// The two are separate because they do not degrade at the same rate: a Qwen encoder that
    /// has lost too much precision garbles the prompt, while the diffusion transformer mostly
    /// loses fine texture. Keeping the encoder at eight bits costs about a gigabyte and is the
    /// first thing to try if a four-bit build stops following prompts.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        adapters: [URL] = []
    ) -> QuantizationPlan {
        let exclusions = WeightPrecisionRule.normsAndEmbeddings + dictionaryModules
        return QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: exclusions,
                    fallback: transformer,
                    adapters: adapters
                ),
                QuantizedComponent(
                    directoryName: "text_encoder", rules: exclusions, fallback: textEncoder),
            ],
            verbatimDirectories: verbatimDirectories
        )
    }

    /// A plan packing every component the same way.
    public static func plan(bits: Int, groupSize: Int) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        return plan(transformer: precision, textEncoder: precision)
    }
}
