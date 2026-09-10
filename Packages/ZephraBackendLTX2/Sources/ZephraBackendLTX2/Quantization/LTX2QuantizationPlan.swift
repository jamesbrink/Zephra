import Foundation
import ZephraQuantization

/// How LTX-2.5 is packed from the `mlx-community/ltx-2.5-mlx` release: which files, which
/// tensors, how finely.
///
/// The release keeps one file per component at its root and the Gemma encoder in a directory
/// of its own, so every component names its source; the build writes the usual one directory
/// per component. Keys keep the release's prefixes (`transformer.`, `connector.`,
/// `vae_decoder.`, `vae_encoder.`, `model.language_model.`) and the kit maps its module paths
/// onto them.
///
/// Video only: every audio-side tensor is omitted, not copied, by `audioOmitted` — the audio
/// stream's blocks, the audio connector and projection, and the four audio-video cross-attention
/// conditioners. The audio variant is this plan without that list.
public enum LTX2QuantizationPlan {
    /// The audio stream, left out of a video-only build. `a2v` and `v2a` catch the two
    /// cross-attention tables and the gate conditioners named for them, `av_ca_` the two
    /// scale-shift conditioners of the same cross-attention, and `audio` the rest.
    public static let audioOmitted: [NamePattern] = [
        .contains("audio"), .contains("a2v"), .contains("v2a"), .prefix("transformer.av_ca_"),
    ]

    /// Transformer tensors held whole: the conditioning that every block reads, the two ends
    /// of the token stream, the modulation tables (float32 in the release), and the per-head
    /// attention gates, which are 32 outputs wide and not worth a manifest entry.
    static let transformerStaysWhole: [NamePattern] = [
        .prefix("transformer.adaln_single."),
        .prefix("transformer.prompt_adaln_single."),
        .prefix("transformer.patchify_proj."),
        .prefix("transformer.proj_out."),
        .contains("scale_shift_table"),
        .contains("to_gate_logits"),
        .contains("keyframes_abs_pos_embedding"),
    ]

    /// Connector tensors held whole: the registers that stand in for padding, the gates, norms.
    /// Spelled out rather than taken from `normsAndEmbeddings`, whose `embed` substring would
    /// match `video_embeddings_connector` and hold the whole stack at full width.
    static let connectorStaysWhole: [NamePattern] = [
        .contains("learnable_registers"),
        .contains("to_gate_logits"),
        .contains("norm"),
    ]

    /// The plan with the two stacks at one precision and the two embeddings at another.
    ///
    /// `embeddings` is the precision for Gemma's 262144-row token table and the 188160-wide
    /// aggregate projection: both are read once per prompt, both lose more than a block does
    /// at four bits (mlx-community's quality notes on the encoder), and together they are 2 GB
    /// at eight bits against 3.5 GB whole.
    public static func plan(
        transformer: QuantizationPrecision,
        textEncoder: QuantizationPrecision,
        embeddings: QuantizationPrecision
    ) -> QuantizationPlan {
        QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    sourceFiles: ["transformer-distilled.safetensors"],
                    rules: transformerStaysWhole.map { WeightPrecisionRule($0, precision: nil) }
                        + WeightPrecisionRule.normsAndEmbeddings,
                    fallback: transformer,
                    omitted: audioOmitted
                ),
                QuantizedComponent(
                    directoryName: "connector",
                    sourceFiles: ["connector.safetensors"],
                    rules: [WeightPrecisionRule(.contains("video_aggregate_embed"), precision: embeddings)]
                        + connectorStaysWhole.map { WeightPrecisionRule($0, precision: nil) },
                    fallback: transformer,
                    omitted: audioOmitted
                ),
                QuantizedComponent(
                    directoryName: "text_encoder",
                    sourceDirectory: "gemma4-12b-ltx-v1",
                    rules: [
                        WeightPrecisionRule(.contains("embed_tokens"), precision: embeddings),
                        WeightPrecisionRule(.contains("layer_scalar"), precision: nil),
                    ] + WeightPrecisionRule.normsAndEmbeddings,
                    fallback: textEncoder
                ),
                // Three-dimensional convolutions cannot be packed; both halves of the
                // autoencoder are copied as they are, into one directory so the loader finds
                // them where every family's autoencoder is. The encoder is what reads a
                // picture held as the clip's first frame; the two files' tensors are told
                // apart by the prefix each carries.
                QuantizedComponent(
                    directoryName: "vae",
                    sourceFiles: ["vae_decoder.safetensors", "vae_encoder.safetensors"],
                    fallback: nil
                ),
                // The spatial latent upscaler the second stage doubles the latent with: a
                // gigabyte of three-dimensional convolutions and group norms, copied as it is.
                QuantizedComponent(
                    directoryName: "upsampler",
                    sourceFiles: ["spatial_upscaler_x2_v1_1.safetensors"],
                    fallback: nil
                ),
            ],
            verbatimDirectories: []
        )
    }

    /// The plan at one precision throughout, except the embeddings, which never go below eight.
    public static func plan(bits: Int, groupSize: Int) throws -> QuantizationPlan {
        let precision = try QuantizationPrecision(bits: bits, groupSize: groupSize)
        let embeddings = bits < 8 ? try QuantizationPrecision(bits: 8, groupSize: groupSize) : precision
        return plan(transformer: precision, textEncoder: precision, embeddings: embeddings)
    }
}
