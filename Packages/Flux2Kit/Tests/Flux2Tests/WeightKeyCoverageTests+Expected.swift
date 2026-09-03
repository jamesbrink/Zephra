import Foundation

@testable import Flux2

/// What the language stack and the transformer must carry, derived from their configurations.
///
/// Written out rather than read back from a module tree on purpose: a tree that is wrong in the
/// same way as the expectation would agree with itself. These are read off the architecture as
/// documented, and the snapshot is the other witness.
extension WeightKeyCoverageTests {
    /// One Qwen3 decoder layer's eleven tensors. Every one is a weight; Qwen3 has no biases.
    static func textEncoderLayerKeys(_ layer: Int) -> [String] {
        let prefix = "model.layers.\(layer)"
        return [
            "\(prefix).input_layernorm.weight",
            "\(prefix).post_attention_layernorm.weight",
            "\(prefix).mlp.gate_proj.weight",
            "\(prefix).mlp.up_proj.weight",
            "\(prefix).mlp.down_proj.weight",
            "\(prefix).self_attn.q_proj.weight",
            "\(prefix).self_attn.k_proj.weight",
            "\(prefix).self_attn.v_proj.weight",
            "\(prefix).self_attn.o_proj.weight",
            // The two that say this is Qwen3 and not Qwen2.5, which instead biases the
            // projections above and norms nothing per head.
            "\(prefix).self_attn.q_norm.weight",
            "\(prefix).self_attn.k_norm.weight",
        ]
    }

    /// Only the layers a tap can reach, plus the embedding. No final norm.
    static func expectedTextEncoderKeys(
        _ configuration: Flux2TextEncoderConfiguration
    ) -> Set<String> {
        var keys: Set<String> = ["model.embed_tokens.weight"]
        for layer in 0..<configuration.layersNeeded {
            keys.formUnion(textEncoderLayerKeys(layer))
        }
        return keys
    }

    /// The transformer's tensors and their shapes: nine global, sixteen per dual-stream block,
    /// four per single-stream block.
    static func expectedTransformerTensors(
        _ configuration: Flux2TransformerConfiguration
    ) -> [String: [Int]] {
        let inner = configuration.innerDim
        let mlp = configuration.mlpDim
        let head = configuration.attentionHeadDim

        // The three modulation matrices are shared by every block of their kind, which is why
        // they are global and why there are only nine of these. Each produces whole sets of
        // shift, scale, and gate: two sets for a dual-stream block, one for a single-stream.
        var tensors: [String: [Int]] = [
            "x_embedder.weight": [inner, configuration.inChannels],
            "context_embedder.weight": [inner, configuration.jointAttentionDim],
            "time_guidance_embed.timestep_embedder.linear_1.weight":
                [inner, configuration.timestepGuidanceChannels],
            "time_guidance_embed.timestep_embedder.linear_2.weight": [inner, inner],
            "double_stream_modulation_img.linear.weight": [6 * inner, inner],
            "double_stream_modulation_txt.linear.weight": [6 * inner, inner],
            "single_stream_modulation.linear.weight": [3 * inner, inner],
            "norm_out.linear.weight": [2 * inner, inner],
            "proj_out.weight": [configuration.outChannels, inner],
        ]

        for block in 0..<configuration.numLayers {
            let prefix = "transformer_blocks.\(block)"
            for projection in [
                "to_q", "to_k", "to_v", "to_out.0",
                "add_q_proj", "add_k_proj", "add_v_proj", "to_add_out",
            ] {
                tensors["\(prefix).attn.\(projection).weight"] = [inner, inner]
            }
            for norm in ["norm_q", "norm_k", "norm_added_q", "norm_added_k"] {
                tensors["\(prefix).attn.\(norm).weight"] = [head]
            }
            // SwiGLU from one matrix: the gate and the value side by side, hence twice the
            // feed-forward width going in and once coming back.
            for stream in ["ff", "ff_context"] {
                tensors["\(prefix).\(stream).linear_in.weight"] = [2 * mlp, inner]
                tensors["\(prefix).\(stream).linear_out.weight"] = [inner, mlp]
            }
        }

        for block in 0..<configuration.numSingleLayers {
            let prefix = "single_transformer_blocks.\(block).attn"
            // Queries, keys, values, and both halves of the feed-forward, from one projection.
            tensors["\(prefix).to_qkv_mlp_proj.weight"] = [configuration.fusedProjectionDim, inner]
            tensors["\(prefix).norm_q.weight"] = [head]
            tensors["\(prefix).norm_k.weight"] = [head]
            // And back from the attention output and the gated feed-forward concatenated.
            tensors["\(prefix).to_out.weight"] = [inner, inner + mlp]
        }

        return tensors
    }
}
