import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendLTX2

@Suite("the LTX-2.5 packing plan")
struct LTX2QuantizationPlanTests {
    private let plan = try! LTX2QuantizationPlan.plan(bits: 4, groupSize: 64)

    private func component(_ name: String) -> QuantizedComponent {
        plan.components.first { $0.directoryName == name }!
    }

    @Test("four components, each naming where the release keeps it")
    func components() {
        #expect(plan.components.map(\.directoryName) == ["transformer", "connector", "text_encoder", "vae"])
        #expect(component("transformer").sourceFiles == ["transformer-distilled.safetensors"])
        #expect(component("text_encoder").sourceDirectory == "gemma4-12b-ltx-v1")
        #expect(component("vae").fallback == nil)
    }

    @Test("every audio-side tensor is omitted from the transformer and the connector")
    func audioOmitted() {
        let transformer = component("transformer")
        for name in [
            "transformer.transformer_blocks.3.audio_attn1.to_q.weight",
            "transformer.transformer_blocks.3.audio_to_video_attn.to_k.weight",
            "transformer.transformer_blocks.3.video_to_audio_attn.to_out.weight",
            "transformer.transformer_blocks.3.scale_shift_table_a2v_ca_video",
            "transformer.av_ca_a2v_gate_adaln_single.linear.weight",
            "transformer.av_ca_video_scale_shift_adaln_single.linear.weight",
            "transformer.audio_patchify_proj.weight",
        ] {
            #expect(transformer.omits(name), Comment(rawValue: name))
        }
        #expect(!transformer.omits("transformer.transformer_blocks.3.attn1.to_q.weight"))
        #expect(!transformer.omits("transformer.adaln_single.linear.weight"))
        let connector = component("connector")
        #expect(connector.omits("connector.audio_embeddings_connector.learnable_registers"))
        #expect(connector.omits("connector.text_embedding_projection.audio_aggregate_embed.weight"))
        #expect(!connector.omits("connector.video_embeddings_connector.transformer_1d_blocks.0.attn1.to_q.weight"))
    }

    @Test("blocks pack at four bits; conditioning, tables, gates and norms stay whole")
    func transformerPrecisions() {
        let transformer = component("transformer")
        #expect(transformer.precision(for: "transformer.transformer_blocks.0.attn1.to_q.weight")?.bits == 4)
        #expect(transformer.precision(for: "transformer.transformer_blocks.0.ff.proj_in.weight")?.bits == 4)
        for whole in [
            "transformer.adaln_single.linear.weight",
            "transformer.adaln_single.emb.timestep_embedder.linear1.weight",
            "transformer.prompt_adaln_single.linear.weight",
            "transformer.patchify_proj.weight",
            "transformer.proj_out.weight",
            "transformer.transformer_blocks.0.scale_shift_table",
            "transformer.transformer_blocks.0.attn1.to_gate_logits.weight",
            "transformer.transformer_blocks.0.attn1.q_norm.weight",
            "transformer.keyframes_abs_pos_embedding",
        ] {
            #expect(transformer.precision(for: whole) == nil, Comment(rawValue: whole))
        }
    }

    @Test("the two embeddings pack at eight bits whatever the rest is set to")
    func embeddings() {
        #expect(component("connector").precision(for: "connector.text_embedding_projection.video_aggregate_embed.weight")?.bits == 8)
        #expect(component("connector").precision(for: "connector.video_embeddings_connector.transformer_1d_blocks.0.ff.net.0.proj.weight")?.bits == 4)
        #expect(component("connector").precision(for: "connector.video_embeddings_connector.learnable_registers") == nil)
        let encoder = component("text_encoder")
        #expect(encoder.precision(for: "model.language_model.embed_tokens.weight")?.bits == 8)
        #expect(encoder.precision(for: "model.language_model.layers.0.mlp.down_proj.weight")?.bits == 4)
        #expect(encoder.precision(for: "model.language_model.layers.0.self_attn.q_norm.weight") == nil)
        #expect(encoder.precision(for: "model.language_model.layers.0.layer_scalar") == nil)
        let eight = try! LTX2QuantizationPlan.plan(bits: 8, groupSize: 64)
        #expect(eight.isUniform)
        #expect(!plan.isUniform)
    }
}
