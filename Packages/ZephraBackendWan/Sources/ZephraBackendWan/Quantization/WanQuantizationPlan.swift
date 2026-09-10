import Foundation
import ZephraQuantization

/// How Wan 2.2 is packed from the FastWan Diffusers release: which directories, which
/// tensors, how finely.
///
/// The release keeps one directory per component, so the build reads each as it is named and
/// keys keep the release's own names; the kit's module paths are those names. The tokenizer
/// is copied whole.
public enum WanQuantizationPlan {
    /// Transformer tensors held whole: the patch embedding (a convolution, which cannot be
    /// packed), the modulation tables (the reference zero-initialises and trains them), the
    /// output projection, which is 192 wide and not worth a manifest entry, and the norms.
    static let transformerStaysWhole: [NamePattern] = [
        .prefix("patch_embedding."),
        .prefix("proj_out."),
        .contains("scale_shift_table"),
    ]

    /// Text-encoder tensors held whole: each layer's relative-position table, 32 buckets by 64
    /// heads, and the norms.
    static let textEncoderStaysWhole: [NamePattern] = [
        .contains("relative_attention_bias"),
    ]

    /// The plan with the two stacks at one precision and the conditioning and token table at
    /// another.
    ///
    /// `conditioning` is the precision for the transformer's `condition_embedder` — the
    /// timestep and text embedders and the 3072-by-18432 modulation projection, which decides
    /// how strongly every block responds and, as Qwen-Image's modulation showed, loses
    /// coherent structure at four bits — and for UMT5's 256384-row token table, read once per
    /// prompt and worth its eight bits.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        conditioning: QuantizationPrecision
    ) -> QuantizationPlan {
        QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: transformerStaysWhole.map { WeightPrecisionRule($0, precision: nil) }
                        + [WeightPrecisionRule(.prefix("condition_embedder."), precision: conditioning)]
                        + WeightPrecisionRule.normsAndEmbeddings,
                    fallback: transformer
                ),
                QuantizedComponent(
                    directoryName: "text_encoder",
                    rules: textEncoderStaysWhole.map { WeightPrecisionRule($0, precision: nil) }
                        + [
                            WeightPrecisionRule(.prefix("shared."), precision: conditioning),
                            WeightPrecisionRule(.contains("embed_tokens"), precision: conditioning),
                        ]
                        + WeightPrecisionRule.normsAndEmbeddings,
                    fallback: textEncoder
                ),
                // Three-dimensional convolutions cannot be packed; the autoencoder is copied as
                // it is, both halves in the one file the release keeps them in.
                QuantizedComponent(directoryName: "vae", fallback: nil),
            ],
            verbatimDirectories: ["tokenizer"]
        )
    }

    /// The plan at one precision throughout, except the conditioning, which never goes below
    /// eight.
    public static func plan(bits: Int, groupSize: Int) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        let conditioning = bits < 8 ? try QuantizationPrecision(bits: 8, groupSize: groupSize) : precision
        return plan(transformer: precision, textEncoder: precision, conditioning: conditioning)
    }
}
