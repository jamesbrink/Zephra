import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendQwenImage

/// What the plan packs, and at what precision.
///
/// The modulation rule is the one with a real cost attached — about 3.4 GB of resident memory
/// — so it is asserted rather than left to a comment.
@Suite("Qwen-Image quantization plan")
struct QwenImageQuantizationPlanTests {
    private static func transformer() throws -> QuantizedComponent {
        let plan = try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        return try #require(plan.components.first { $0.directoryName == "transformer" })
    }

    @Test("both streams' modulation layers are held at eight bits")
    func modulationStaysCoarse() throws {
        let component = try Self.transformer()
        #expect(component.precision(for: "transformer_blocks.0.img_mod.1.weight")?.bits == 8)
        #expect(component.precision(for: "transformer_blocks.59.txt_mod.1.weight")?.bits == 8)
    }

    @Test("ordinary projections go to four bits")
    func everythingElseIsFine() throws {
        let component = try Self.transformer()
        for name in [
            "transformer_blocks.0.attn.to_q.weight",
            "transformer_blocks.0.attn.add_k_proj.weight",
            "transformer_blocks.0.img_mlp.net.0.proj.weight",
            "transformer_blocks.0.txt_mlp.net.2.weight",
            "img_in.weight",
            "proj_out.weight",
        ] {
            #expect(component.precision(for: name)?.bits == 4, "\(name)")
        }
    }

    @Test("norms are left alone, and so is the rotary-adjacent naming that looks like one")
    func normsAreExcluded() throws {
        let component = try Self.transformer()
        #expect(component.precision(for: "transformer_blocks.0.attn.norm_q.weight") == nil)
        #expect(component.precision(for: "txt_norm.weight") == nil)
    }

    @Test("the timestep embedder and the output projection are left whole, on purpose")
    func conditioningLinearsStayWhole() throws {
        let component = try Self.transformer()
        // Both would pass QuantizableWeight's shape test, so only a rule keeps them out.
        for name in [
            "time_text_embed.timestep_embedder.linear_1.weight",
            "time_text_embed.timestep_embedder.linear_2.weight",
            "norm_out.linear.weight",
        ] {
            #expect(component.precision(for: name) == nil, "\(name)")
        }
    }

    @Test("the text encoder's vision tower and language head are left out of the build")
    func unusedTextEncoderWeightsAreOmitted() throws {
        let plan = try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        let encoder = try #require(plan.components.first { $0.directoryName == "text_encoder" })
        // Omitted, not merely unpacked: nothing ever loads either, so copying them across at
        // full precision would spend 2.4 GB of disk and the same again in the read on tensors
        // no module tree asks for. A norm is the other case — unpacked, but copied.
        #expect(encoder.omits("visual.blocks.0.attn.qkv.weight"))
        #expect(encoder.omits("lm_head.weight"))
        #expect(!encoder.omits("model.layers.0.self_attn.q_proj.weight"))
        #expect(!encoder.omits("model.layers.0.input_layernorm.weight"))
        #expect(encoder.precision(for: "model.layers.0.input_layernorm.weight") == nil)
        #expect(encoder.precision(for: "model.layers.0.self_attn.q_proj.weight")?.bits == 4)
    }

    @Test("the four-step adapter is merged into the transformer and nothing else")
    func adaptersReachOnlyTheTransformer() throws {
        let adapter = URL(filePath: "/tmp/lightning.safetensors")
        let plan = try QwenImageQuantizationPlan.plan(
            bits: 4, groupSize: 64, adapters: [adapter])
        for component in plan.components {
            #expect(
                component.adapters == (component.directoryName == "transformer" ? [adapter] : []),
                "the distillation is the transformer's; merging it into the text encoder would name weights that component has not got and stop the build"
            )
        }
        #expect(try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
            .components.allSatisfy { $0.adapters.isEmpty })
    }

    @Test("the VAE is carried across whole rather than packed")
    func vaeStaysWhole() throws {
        let plan = try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        #expect(plan.verbatimDirectories.contains("vae"))
        #expect(!plan.components.contains { $0.directoryName == "vae" })
        #expect(!plan.isUniform, "modulation at eight bits makes this a mixed build")
    }
}
