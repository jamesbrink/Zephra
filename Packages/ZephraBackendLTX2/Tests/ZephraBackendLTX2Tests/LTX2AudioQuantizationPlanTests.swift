import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendLTX2

@Suite("the LTX-2.5 packing plan with the audio lane")
struct LTX2AudioQuantizationPlanTests {
    private let plan = try! LTX2QuantizationPlan.plan(bits: 4, groupSize: 64, audio: true)

    private func component(_ name: String) -> QuantizedComponent {
        plan.components.first { $0.directoryName == name }!
    }

    @Test("the video plan's five components and then the audio decoder and the vocoder")
    func components() {
        #expect(
            plan.components.map(\.directoryName)
                == ["transformer", "connector", "text_encoder", "vae", "upsampler", "audio_vae", "vocoder"])
        #expect(component("audio_vae").sourceFiles == ["audio_vae.safetensors"])
        #expect(component("audio_vae").fallback == nil)
        #expect(component("vocoder").sourceFiles == ["vocoder.safetensors"])
        #expect(component("vocoder").fallback == nil)
    }

    @Test("nothing on the audio side is omitted from the transformer or the connector")
    func audioKept() {
        let transformer = component("transformer")
        for name in [
            "transformer.transformer_blocks.3.audio_attn1.to_q.weight",
            "transformer.transformer_blocks.3.audio_to_video_attn.to_k.weight",
            "transformer.av_ca_a2v_gate_adaln_single.linear.weight",
            "transformer.audio_patchify_proj.weight",
        ] {
            #expect(!transformer.omits(name), Comment(rawValue: name))
        }
        let connector = component("connector")
        #expect(!connector.omits("connector.audio_embeddings_connector.learnable_registers"))
        #expect(!connector.omits("connector.text_embedding_projection.audio_aggregate_embed.weight"))
    }

    @Test("the lane's blocks pack at four bits; its ends, adaLN heads and conditioners stay whole")
    func precisions() {
        let transformer = component("transformer")
        #expect(transformer.precision(for: "transformer.transformer_blocks.0.audio_attn1.to_q.weight")?.bits == 4)
        #expect(transformer.precision(for: "transformer.transformer_blocks.0.audio_ff.net.0.proj.weight")?.bits == 4)
        #expect(transformer.precision(for: "transformer.transformer_blocks.0.audio_to_video_attn.to_q.weight")?.bits == 4)
        for whole in [
            "transformer.audio_adaln_single.linear.weight",
            "transformer.audio_prompt_adaln_single.linear.weight",
            "transformer.av_ca_a2v_gate_adaln_single.linear.weight",
            "transformer.av_ca_audio_scale_shift_adaln_single.linear.weight",
            "transformer.audio_patchify_proj.weight",
            "transformer.audio_proj_out.weight",
            "transformer.audio_scale_shift_table",
            "transformer.transformer_blocks.0.audio_scale_shift_table",
            "transformer.transformer_blocks.0.scale_shift_table_a2v_ca_audio",
            "transformer.transformer_blocks.0.audio_attn1.to_gate_logits.weight",
        ] {
            #expect(transformer.precision(for: whole) == nil, Comment(rawValue: whole))
        }
        #expect(component("connector").precision(for: "connector.text_embedding_projection.audio_aggregate_embed.weight")?.bits == 8)
        #expect(component("connector").precision(for: "connector.audio_embeddings_connector.transformer_1d_blocks.0.attn1.to_q.weight")?.bits == 4)
    }

    @Test("the audio encoder and the vocoder's inverse basis are left out; nothing else is")
    func copiedWhole() {
        let decoder = component("audio_vae")
        #expect(decoder.omits("audio_vae.encoder.conv_in.weight"))
        #expect(!decoder.omits("audio_vae.decoder.conv_in.weight"))
        #expect(!decoder.omits("audio_vae.per_channel_statistics._mean_of_means"))
        #expect(decoder.precision(for: "audio_vae.decoder.conv_in.weight") == nil)
        let vocoder = component("vocoder")
        #expect(vocoder.omits("vocoder.mel_stft.stft_fn.inverse_basis"))
        #expect(!vocoder.omits("vocoder.mel_stft.stft_fn.forward_basis"))
        #expect(!vocoder.omits("vocoder.ups.0.weight"))
        #expect(vocoder.precision(for: "vocoder.ups.0.weight") == nil)
    }

    @Test("the video-only plan is unchanged by the lane existing")
    func videoOnlyUnchanged() {
        let video = try! LTX2QuantizationPlan.plan(bits: 4, groupSize: 64)
        #expect(video.components.map(\.directoryName) == ["transformer", "connector", "text_encoder", "vae", "upsampler"])
        #expect(video.components[0].omits("transformer.audio_patchify_proj.weight"))
    }
}
