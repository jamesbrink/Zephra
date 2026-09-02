import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendQwenImage

/// What the plan packs, and at what precision.
///
/// The modulation rule is the one with a real cost attached — roughly 2.4 GB of resident memory
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

    @Test("the text encoder's vision tower and language head are never packed")
    func unusedTextEncoderWeightsAreSkipped() throws {
        let plan = try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        let encoder = try #require(plan.components.first { $0.directoryName == "text_encoder" })
        // Neither is ever loaded, so packing them would spend time and space on nothing.
        #expect(encoder.precision(for: "visual.blocks.0.attn.qkv.weight") == nil)
        #expect(encoder.precision(for: "lm_head.weight") == nil)
        #expect(encoder.precision(for: "model.layers.0.self_attn.q_proj.weight")?.bits == 4)
    }

    @Test("the VAE is carried across whole rather than packed")
    func vaeStaysWhole() throws {
        let plan = try QwenImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        #expect(plan.verbatimDirectories.contains("vae"))
        #expect(!plan.components.contains { $0.directoryName == "vae" })
        #expect(!plan.isUniform, "modulation at eight bits makes this a mixed build")
    }
}
