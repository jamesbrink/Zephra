import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendQwenImage21

@Suite("The Qwen-Image 2.1 packing plan")
struct QwenImage21QuantizationPlanTests {
    private func plan() throws -> QuantizationPlan {
        try QwenImage21QuantizationPlan.plan(bits: 4, groupSize: 64)
    }
    private func transformer() throws -> QuantizedComponent { try plan().components[0] }
    private func textEncoder() throws -> QuantizedComponent { try plan().components[1] }

    @Test("block projections pack, and everything that conditions them stays whole")
    func transformerRules() throws {
        let transformer = try transformer()
        // Every name below is spelled as the release's own shard index spells it.
        for name in [
            "transformer_blocks.0.attn.to_q.weight",
            "transformer_blocks.31.attn.to_k.weight",
            "transformer_blocks.7.attn.to_v.weight",
            "transformer_blocks.7.attn.to_out.0.weight",
            "transformer_blocks.12.img_mlp.gate_layer.weight",
            "transformer_blocks.12.img_mlp.proj.weight",
            "transformer_blocks.12.img_mlp.out.weight",
        ] {
            #expect(transformer.precision(for: name)?.bits == 4, Comment(rawValue: name))
        }
        for name in [
            "modulation.1.weight", "img_in.weight", "proj_out.weight",
            "norm_out.linear.weight",
            "time_text_embed.timestep_embedder.linear_1.weight",
            "time_text_embed.timestep_embedder.linear_2.weight",
            "transformer_blocks.0.attn.norm_q.weight",
            "transformer_blocks.31.attn.norm_k.weight",
            // Claimed by the norm rule above `txt_in.`, not refused later on its shape.
            "txt_in.text_norm.weight",
        ] {
            #expect(transformer.precision(for: name) == nil, Comment(rawValue: name))
        }
        for name in ["txt_in.in_layer.weight", "txt_in.out_layer.weight"] {
            #expect(transformer.precision(for: name)?.bits == 8, Comment(rawValue: name))
        }
    }

    @Test("the encoder and the tower pack their stacks, hold their tables, and omit two tensors")
    func textEncoderRules() throws {
        let textEncoder = try textEncoder()
        for name in [
            "model.language_model.layers.0.self_attn.q_proj.weight",
            "model.language_model.layers.35.mlp.down_proj.weight",
            "model.visual.blocks.0.attn.qkv.weight",
            "model.visual.blocks.26.mlp.linear_fc2.weight",
            "model.visual.merger.linear_fc1.weight",
            "model.visual.deepstack_merger_list.2.linear_fc2.weight",
        ] {
            #expect(textEncoder.precision(for: name)?.bits == 4, Comment(rawValue: name))
        }
        #expect(textEncoder.precision(for: "model.language_model.embed_tokens.weight")?.bits == 8)
        for name in [
            "model.visual.pos_embed.weight", "model.visual.patch_embed.proj.weight",
            "model.language_model.layers.3.input_layernorm.weight",
            "model.language_model.layers.3.post_attention_layernorm.weight",
            "model.language_model.layers.3.self_attn.q_norm.weight",
            "model.visual.blocks.0.norm1.weight", "model.visual.merger.norm.weight",
            "model.visual.blocks.0.attn.qkv.bias", "model.visual.patch_embed.proj.bias",
        ] {
            #expect(textEncoder.precision(for: name) == nil, Comment(rawValue: name))
        }
        #expect(textEncoder.omits("lm_head.weight"))
        #expect(textEncoder.omits("model.language_model.norm.weight"))
        // The trailing dot on the omitted prefix is what keeps the stack's own norms in.
        #expect(!textEncoder.omits("model.language_model.layers.0.input_layernorm.weight"))
        #expect(!textEncoder.omits("model.language_model.layers.0.self_attn.q_proj.weight"))
    }

    @Test("nothing the plan packs is a shape the packer would refuse at group 64")
    func packedShapesDivide() throws {
        let (transformer, textEncoder) = (try transformer(), try textEncoder())
        // Shapes read off the release's own safetensors headers.
        let shapes: [(String, [Int])] = [
            ("transformer_blocks.0.attn.to_q.weight", [4096, 4096]),
            ("transformer_blocks.0.attn.to_out.0.weight", [4096, 4096]),
            ("transformer_blocks.0.img_mlp.gate_layer.weight", [12288, 4096]),
            ("transformer_blocks.0.img_mlp.out.weight", [4096, 12288]),
            ("txt_in.in_layer.weight", [4096, 4096]),
            ("model.language_model.embed_tokens.weight", [151936, 4096]),
            ("model.language_model.layers.0.self_attn.k_proj.weight", [1024, 4096]),
            ("model.language_model.layers.0.mlp.down_proj.weight", [4096, 12288]),
            ("model.visual.blocks.0.attn.qkv.weight", [3456, 1152]),
            ("model.visual.blocks.0.mlp.linear_fc1.weight", [4304, 1152]),
            ("model.visual.merger.linear_fc1.weight", [4608, 4608]),
        ]
        for (name, shape) in shapes {
            let component = name.hasPrefix("model.") ? textEncoder : transformer
            let precision = component.precision(for: name)
            #expect(precision != nil, Comment(rawValue: name))
            #expect(
                QuantizableWeight(name: name, shape: shape, groupSize: precision?.groupSize ?? 64)
                    != nil, Comment(rawValue: name))
        }
    }

    @Test("the autoencoder, processor and scheduler are copied verbatim, and a build is mixed")
    func verbatimAndMixed() throws {
        let plan = try plan()
        #expect(plan.verbatimDirectories == ["vae", "processor", "scheduler"])
        // Not uniform: `txt_in` and the vocabulary table stay at eight while the stacks go to
        // four, which is what the per-layer manifest exists to describe.
        #expect(!plan.isUniform)
        // An eight-bit build has nothing to raise, so it is one precision throughout.
        #expect(try QwenImage21QuantizationPlan.plan(bits: 8, groupSize: 64).isUniform)
    }

    @Test("the variant carries the attribution the Qwen research license asks for")
    func noticeIsWritten() throws {
        let notice = try #require(try plan().notice)
        #expect(notice.hasPrefix("Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT,"))
        #expect(notice.contains("Hangzhou Tongyi Laboratory Technology Co., Ltd."))
        #expect(notice.hasSuffix("All Rights Reserved."))
    }
}
