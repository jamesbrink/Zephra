import Foundation
import ZephraQuantization

/// How Qwen-Image 2.1 is packed: which directories, which tensors, how finely.
///
/// Two components and three verbatim directories. Every pattern below is spelled the way the
/// **release's own shard indexes** spell it, because that is what the packer matches against —
/// `modulation.1.weight`, `transformer_blocks.0.attn.to_out.0.weight`, `model.visual.*` — and
/// the manifest the packer writes is keyed the same way, which is the spelling
/// `QwenImage21TransformerWeights.checkpointName(of:)` and `Qwen3VLTextWeights` hand back to
/// `PackedWeightLoading` and to `LayerWeightStream`. A rule written in module-tree spelling
/// would silently claim nothing.
///
/// What 2512 taught and this keeps: modulation stays whole. It is one 16384 × 4096 table every
/// one of the 32 blocks reads, 134 MB at bfloat16, and four-bit builds that packed the 2512
/// equivalent lost coherent structure for a saving that rounds to nothing.
public enum QwenImage21QuantizationPlan {
    /// Copied across whole. The autoencoder is 1.35 GB, runs once per picture rather than once
    /// per step, and its artefacts land directly on the pixels; `processor` carries the
    /// tokenizer, which 2.1 publishes there rather than in a `tokenizer/` of its own.
    static let verbatimDirectories = ["vae", "processor", "scheduler"]

    /// The attribution the Qwen RESEARCH LICENSE AGREEMENT requires every copy of the weights
    /// to carry in a `Notice` text file (clause 3.c), quoted from the release's own `LICENSE`.
    /// `SnapshotAncillaryFiles` writes it as `NOTICE` beside the copied `LICENSE`.
    static let notice = """
        Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT, \
        Copyright (c) 2026 Hangzhou Tongyi Laboratory Technology Co., Ltd. All Rights Reserved.
        """

    /// Left at full precision in the transformer, most specific first.
    ///
    /// The norm rule sits **above** `txt_in.`, not below it as the block table reads: the
    /// prefix would otherwise claim `txt_in.text_norm.weight`, a 4096-long vector the packer
    /// would then have to refuse on shape. Refusing on shape gives the right file and the wrong
    /// reason, and a reason that stops being right the day a norm arrives two-dimensional.
    static let transformerWhole: [NamePattern] = [
        .contains("modulation."),  // one 16384 x 4096 table all 32 blocks read
        .prefix("img_in."),  // 4096 x 64, the latent's only door in
        .prefix("proj_out."),  // 64 x 4096, and its only door out
        .prefix("time_text_embed."),  // the timestep embedder, 1 M parameters
        .prefix("norm_out."),
        .contains("norm"),  // attn.norm_q, attn.norm_k, txt_in.text_norm
    ]

    /// Left at full precision in the text encoder, most specific first. `embed_tokens` is not
    /// here: it is claimed at eight bits above these, which is why this list may use the broad
    /// `embed` substring that `WeightPrecisionRule.normsAndEmbeddings` uses.
    static let textEncoderWhole: [NamePattern] = [
        .contains("pos_embed"),  // the tower's learned 2304 x 1152 table
        .contains("patch_embed"),  // 5-D, and nothing MLX can pack
        .contains("norm"),  // the decoder's four norms a layer, the tower's three a block
        .suffix(".bias"),  // the tower's only 1-D parameters
    ]

    /// Never built, never loaded. `lm_head.weight` is 1.25 GB of vocabulary projection this
    /// port never reaches, and the decoder's final norm is read by nothing once the hidden
    /// state is taken from the layer stack. The **trailing dot is load-bearing** on the second:
    /// without it the pattern would also catch every `input_layernorm` in the stack.
    static let textEncoderOmitted: [NamePattern] = [
        .prefix("lm_head."),
        .prefix("model.language_model.norm."),
    ]

    /// The plan with the block stacks at `transformer` and `textEncoder`, and the tensors read
    /// once by every token — the text projection in, the vocabulary table — at `sensitive`.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        sensitive: QuantizationPrecision
    ) -> QuantizationPlan {
        QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: transformerWhole.map { WeightPrecisionRule($0, precision: nil) }
                        + [WeightPrecisionRule(.prefix("txt_in."), precision: sensitive)],
                    fallback: transformer
                ),
                QuantizedComponent(
                    directoryName: "text_encoder",
                    rules: [WeightPrecisionRule(.contains("embed_tokens"), precision: sensitive)]
                        + textEncoderWhole.map { WeightPrecisionRule($0, precision: nil) },
                    fallback: textEncoder,
                    omitted: textEncoderOmitted
                ),
            ],
            verbatimDirectories: verbatimDirectories,
            notice: notice
        )
    }

    /// The plan at one precision throughout, except that a four-bit build keeps its sensitive
    /// set at eight, which is the trade the 2512 plan made and this one inherits: the two
    /// `txt_in` projections are 16.8 M parameters each and every text token goes through them
    /// once, and the 151936 x 4096 vocabulary table is 1.25 GB at bfloat16 and about 700 MB at
    /// eight bits, where four would be the one saving a prompt notices.
    public static func plan(bits: Int, groupSize: Int) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        let sensitive =
            bits < 8 ? try QuantizationPrecision(bits: 8, groupSize: groupSize) : precision
        return plan(transformer: precision, textEncoder: precision, sensitive: sensitive)
    }
}
