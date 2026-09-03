import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendFlux2

@Suite("The klein packing plan")
struct Flux2QuantizationPlanTests {
    private let plan = try! Flux2QuantizationPlan.plan(bits: 4, groupSize: 64)
    private var transformer: QuantizedComponent { plan.components[0] }
    private var textEncoder: QuantizedComponent { plan.components[1] }

    @Test("block projections pack, and everything that conditions them stays whole")
    func transformerRules() {
        for name in [
            "transformer_blocks.0.attn.to_q.weight",
            "transformer_blocks.4.ff_context.linear_in.weight",
            "single_transformer_blocks.19.attn.to_qkv_mlp_proj.weight",
            "single_transformer_blocks.0.attn.to_out.weight",
        ] {
            #expect(transformer.precision(for: name)?.bits == 4, Comment(rawValue: name))
        }
        for name in [
            "x_embedder.weight", "context_embedder.weight", "proj_out.weight",
            "norm_out.linear.weight",
            "time_guidance_embed.timestep_embedder.linear_1.weight",
            "double_stream_modulation_img.linear.weight",
            "double_stream_modulation_txt.linear.weight",
            "single_stream_modulation.linear.weight",
            "transformer_blocks.0.attn.norm_q.weight",
            "single_transformer_blocks.3.attn.norm_k.weight",
        ] {
            #expect(transformer.precision(for: name) == nil, Comment(rawValue: name))
        }
    }

    @Test("the encoder packs its first 27 layers and omits the rest and the final norm")
    func textEncoderRules() {
        #expect(textEncoder.precision(for: "model.layers.0.self_attn.q_proj.weight")?.bits == 4)
        #expect(textEncoder.precision(for: "model.layers.26.mlp.down_proj.weight")?.bits == 4)
        #expect(textEncoder.precision(for: "model.embed_tokens.weight") == nil)
        #expect(textEncoder.precision(for: "model.layers.3.self_attn.q_norm.weight") == nil)
        #expect(!textEncoder.omits("model.layers.3.self_attn.q_proj.weight"))
        #expect(!textEncoder.omits("model.layers.26.self_attn.q_proj.weight"))
        #expect(textEncoder.omits("model.layers.27.self_attn.q_proj.weight"))
        #expect(textEncoder.omits("model.layers.30.self_attn.q_proj.weight"))
        #expect(textEncoder.omits("model.layers.35.mlp.up_proj.weight"))
        #expect(textEncoder.omits("model.norm.weight"))
    }

    @Test("nothing the plan packs is a shape the packer would refuse at group 64")
    func packedShapesDivide() {
        let shapes: [(String, [Int])] = [
            ("transformer_blocks.0.attn.to_q.weight", [3072, 3072]),
            ("transformer_blocks.0.ff.linear_in.weight", [18432, 3072]),
            ("transformer_blocks.0.ff.linear_out.weight", [3072, 9216]),
            ("single_transformer_blocks.0.attn.to_qkv_mlp_proj.weight", [27648, 3072]),
            ("single_transformer_blocks.0.attn.to_out.weight", [3072, 12288]),
            ("model.layers.0.self_attn.q_proj.weight", [4096, 2560]),
            ("model.layers.0.self_attn.k_proj.weight", [1024, 2560]),
            ("model.layers.0.self_attn.o_proj.weight", [2560, 4096]),
            ("model.layers.0.mlp.gate_proj.weight", [9728, 2560]),
            ("model.layers.0.mlp.down_proj.weight", [2560, 9728]),
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

    @Test("the VAE, tokenizer, and scheduler are copied verbatim, and the plan is uniform")
    func verbatimAndUniform() {
        #expect(plan.verbatimDirectories == ["tokenizer", "scheduler", "vae"])
        #expect(plan.isUniform)
        let mixed = Flux2QuantizationPlan.plan(
            transformer: try! QuantizationPrecision(bits: 4, groupSize: 64),
            textEncoder: try! QuantizationPrecision(bits: 8, groupSize: 64))
        #expect(!mixed.isUniform)
    }
}
