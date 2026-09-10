import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendWan

@Suite("the Wan 2.2 packing plan")
struct WanQuantizationPlanTests {
    private let plan = try! WanQuantizationPlan.plan(bits: 4, groupSize: 64)

    private func component(_ name: String) -> QuantizedComponent {
        plan.components.first { $0.directoryName == name }!
    }

    @Test("three components read as the release names them, and the tokenizer is copied whole")
    func components() {
        #expect(plan.components.map(\.directoryName) == ["transformer", "text_encoder", "vae"])
        for component in plan.components {
            #expect(component.sourceDirectory == nil, Comment(rawValue: component.directoryName))
            #expect(component.sourceFiles.isEmpty, Comment(rawValue: component.directoryName))
        }
        // Three-dimensional convolutions cannot be packed; the autoencoder is copied as it is.
        #expect(component("vae").fallback == nil)
        #expect(plan.verbatimDirectories == ["tokenizer"])
    }

    @Test("blocks pack at four bits; the patch embedding, tables, projection and norms stay whole")
    func transformerPrecisions() {
        let transformer = component("transformer")
        #expect(transformer.precision(for: "blocks.0.attn1.to_q.weight")?.bits == 4)
        #expect(transformer.precision(for: "blocks.29.ffn.net.2.weight")?.bits == 4)
        #expect(transformer.precision(for: "blocks.0.attn2.to_out.0.weight")?.bits == 4)
        for whole in [
            "patch_embedding.weight",
            "patch_embedding.bias",
            "proj_out.weight",
            "scale_shift_table",
            "blocks.0.scale_shift_table",
            "blocks.0.norm2.weight",
            "blocks.0.attn1.norm_q.weight",
        ] {
            #expect(transformer.precision(for: whole) == nil, Comment(rawValue: whole))
        }
    }

    @Test("the conditioning and the token table pack at eight bits whatever the rest is set to")
    func conditioning() {
        let transformer = component("transformer")
        #expect(transformer.precision(for: "condition_embedder.time_proj.weight")?.bits == 8)
        #expect(transformer.precision(for: "condition_embedder.time_embedder.linear_1.weight")?.bits == 8)
        #expect(transformer.precision(for: "condition_embedder.text_embedder.linear_2.weight")?.bits == 8)
        let encoder = component("text_encoder")
        #expect(encoder.precision(for: "shared.weight")?.bits == 8)
        #expect(encoder.precision(for: "encoder.embed_tokens.weight")?.bits == 8)
        #expect(encoder.precision(for: "encoder.block.0.layer.0.SelfAttention.q.weight")?.bits == 4)
        #expect(encoder.precision(for: "encoder.block.0.layer.1.DenseReluDense.wi_0.weight")?.bits == 4)
        #expect(encoder.precision(for: "encoder.block.0.layer.0.SelfAttention.relative_attention_bias.weight") == nil)
        #expect(encoder.precision(for: "encoder.block.0.layer.0.layer_norm.weight") == nil)
        #expect(encoder.precision(for: "encoder.final_layer_norm.weight") == nil)
        let eight = try! WanQuantizationPlan.plan(bits: 8, groupSize: 64)
        #expect(eight.isUniform)
        #expect(!plan.isUniform)
    }
}
