import Foundation
import ZephraQuantization

/// How a Qwen-Image snapshot is packed.
///
/// The interesting decision is the modulation layers. Each block projects the conditioning
/// vector to six times the model's width, twice — once per stream — which comes to 6.8 of the
/// transformer's 20.4 billion parameters. A third of the model is modulation, and it is the part
/// that decides how strongly every other part responds. Published four-bit builds that pack it
/// with everything else are reported to lose coherent structure, so it is held at eight bits
/// here: about 2.4 GB more resident, against a model that follows its own conditioning.
///
/// The VAE is not packed at all. It is a quarter of a gigabyte, it runs once per image rather
/// than once per step, and quantization artefacts in it land directly on the pixels.
public enum QwenImageQuantizationPlan {
    /// Directories carried across whole.
    static let verbatimDirectories = ["tokenizer", "scheduler", "vae"]

    /// The layers held at higher precision than the rest of the transformer.
    static let precisionSensitive = [NamePattern.contains("_mod.")]

    /// A plan packing the transformer and the text encoder at the given precisions, with the
    /// modulation layers held at `modulation`.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        modulation: QuantizationPrecision
    ) -> QuantizationPlan {
        let exclusions = WeightPrecisionRule.normsAndEmbeddings
        return QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: exclusions
                        + precisionSensitive.map {
                            WeightPrecisionRule($0, precision: modulation)
                        },
                    fallback: transformer
                ),
                QuantizedComponent(
                    directoryName: "text_encoder",
                    rules: exclusions,
                    fallback: textEncoder,
                    // Text-to-image supplies no pixels and conditions on hidden states rather
                    // than logits, so neither the vision tower nor the language-modelling head
                    // is ever loaded. Leaving them out saves about 2.4 GB on disk and the same
                    // again in the read.
                    omitted: [.prefix("visual."), .prefix("lm_head")]
                ),
            ],
            verbatimDirectories: verbatimDirectories
        )
    }

    /// A plan at one precision throughout, except the modulation layers, which stay at eight
    /// bits whenever the rest is finer than that.
    public static func plan(bits: Int, groupSize: Int) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        let modulation =
            bits < 8 ? try QuantizationPrecision(bits: 8, groupSize: groupSize) : precision
        return plan(transformer: precision, textEncoder: precision, modulation: modulation)
    }
}
