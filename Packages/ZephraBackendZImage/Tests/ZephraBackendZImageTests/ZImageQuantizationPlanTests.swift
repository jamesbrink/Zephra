import Foundation
import Testing
import ZephraQuantization

@testable import ZephraBackendZImage

/// The reference eight-bit export packs 522 layers and leaves everything else alone. Getting
/// that set wrong produces a snapshot the loader half-applies — it loads, and then paints colour
/// blobs — so the rule is pinned here against real tensor names taken from both repositories.
@Suite("Z-Image quantization plan")
struct ZImageQuantizationPlanTests {
    /// Whether the plan would pack `name`, asked exactly the way the quantizer asks it: the
    /// plan chooses a precision first, then MLX's mechanics are tested at that group size.
    private static func packs(_ name: String, shape: [Int]) throws -> Bool {
        let component = try #require(
            ZImageQuantizationPlan.plan(bits: 4, groupSize: 64).components.first)
        guard let precision = component.precision(for: name) else { return false }
        return QuantizableWeight(name: name, shape: shape, groupSize: precision.groupSize) != nil
    }

    @Test("a transformer linear weight is packed")
    func transformerLinear() throws {
        #expect(try Self.packs("layers.0.attention.to_q.weight", shape: [3840, 3840]))
    }

    @Test("a text encoder projection is packed")
    func textEncoderProjection() throws {
        #expect(try Self.packs("model.layers.0.mlp.down_proj.weight", shape: [2560, 9728]))
    }

    @Test("the adaLN modulation inside a block is packed, unlike the final layer's")
    func adaLNModulation() throws {
        #expect(try Self.packs("layers.0.adaLN_modulation.0.weight", shape: [15360, 256]))
        #expect(
            try !Self.packs(
                "all_final_layer.2-1.adaLN_modulation.1.weight", shape: [3840, 256]),
            "the loader restores this submodule by hand, so a .scales key here breaks the tree")
    }

    @Test("norms, embeddings, biases, and one-dimensional tensors are left alone")
    func passthroughTensors() throws {
        let cases: [(String, [Int])] = [
            ("layers.0.attention_norm1.weight", [3840]),
            ("layers.0.attention.norm_q.weight", [128]),
            ("model.layers.0.input_layernorm.weight", [2560]),
            ("model.embed_tokens.weight", [151_936, 2560]),
            ("layers.0.adaLN_modulation.0.bias", [15360]),
            ("all_x_embedder.2-1.weight", [3840, 64]),
            ("x_pad_token", [1, 3840]),
        ]
        for (name, shape) in cases {
            #expect(try !Self.packs(name, shape: shape), "\(name) should not be packed")
        }
    }

    @Test("the text encoder can be kept at a different precision from the transformer")
    func mixedPlan() throws {
        let plan = ZImageQuantizationPlan.plan(
            transformer: try QuantizationPrecision(bits: 4, groupSize: 64),
            textEncoder: try QuantizationPrecision(bits: 8, groupSize: 32)
        )
        #expect(!plan.isUniform)
        #expect(plan.components.map(\.directoryName) == ["transformer", "text_encoder"])
        #expect(
            plan.components[1].precision(for: "model.layers.0.mlp.down_proj.weight")?.bits == 8)
        #expect(try ZImageQuantizationPlan.plan(bits: 4, groupSize: 64).isUniform)
    }

    @Test("the VAE is carried across whole rather than packed")
    func vaeStaysWhole() throws {
        let plan = try ZImageQuantizationPlan.plan(bits: 4, groupSize: 64)
        #expect(plan.verbatimDirectories.contains("vae"))
        #expect(!plan.components.contains { $0.directoryName == "vae" })
    }
}
