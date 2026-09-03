import Foundation
import ZephraQuantization

/// How FLUX.2 klein is packed: which directories, which tensors, how finely.
///
/// Two things differ from the Qwen-Image plan. The three modulation linears are held whole
/// rather than at a precision of their own: they are 142 million parameters in all, under 300
/// megabytes at bfloat16, so there is nothing to trade. And the text encoder's last nine layers
/// and final norm are omitted, not copied: the transformer conditions on the hidden state after
/// the twenty-seventh layer, so nothing past it is ever read, and a copy would be 1.3 GB of
/// weights nothing loads.
public enum Flux2QuantizationPlan {
    /// Copied across whole. The autoencoder is 168 MB, runs once per image rather than once per
    /// step, and its artefacts land directly on the pixels.
    static let verbatimDirectories = ["tokenizer", "scheduler", "vae"]

    /// Left at full precision on purpose. `WeightPrecisionRule.normsAndEmbeddings` already
    /// catches the first four by substring; they are named here so it reads as a decision
    /// rather than a coincidence, and so a rename cannot silently start packing them.
    static let conditioningStaysWhole: [NamePattern] = [
        .prefix("time_guidance_embed."),  // every block's conditioning goes through it
        .prefix("norm_out."),
        .prefix("x_embedder"),
        .prefix("context_embedder"),  // the only door the text stream enters by
        .prefix("proj_out"),  // not caught by the generic rules
        .prefix("double_stream_modulation_img."),
        .prefix("double_stream_modulation_txt."),
        .prefix("single_stream_modulation."),
    ]

    /// Never built, never loaded. The trailing dot on each layer prefix is load-bearing:
    /// without it `model.layers.3` would also match layers 30 to 35.
    static let textEncoderOmitted: [NamePattern] =
        (27...35).map { NamePattern.prefix("model.layers.\($0).") } + [.prefix("model.norm.")]

    /// The plan for the transformer at one precision and the text encoder at another.
    ///
    /// `adapters` is accepted for the day a klein adapter is worth merging; the release ships
    /// none, and the distillation is already in the weights.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        adapters: [URL] = []
    ) -> QuantizationPlan {
        QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: WeightPrecisionRule.normsAndEmbeddings
                        + conditioningStaysWhole.map { WeightPrecisionRule($0, precision: nil) },
                    fallback: transformer,
                    adapters: adapters
                ),
                QuantizedComponent(
                    directoryName: "text_encoder",
                    rules: WeightPrecisionRule.normsAndEmbeddings,
                    fallback: textEncoder,
                    omitted: textEncoderOmitted
                ),
            ],
            verbatimDirectories: verbatimDirectories
        )
    }

    /// The plan at one precision throughout.
    public static func plan(bits: Int, groupSize: Int, adapters: [URL] = []) throws
        -> QuantizationPlan
    {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        return plan(transformer: precision, textEncoder: precision, adapters: adapters)
    }
}
