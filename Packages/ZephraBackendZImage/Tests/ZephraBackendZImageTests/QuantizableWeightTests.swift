import Foundation
import Testing

@testable import ZephraBackendZImage

/// The reference eight-bit export packs 522 layers and leaves everything else alone. Getting
/// that set wrong produces a snapshot the loader half-applies, so the rule is pinned here
/// against real tensor names taken from both repositories.
@Suite("QuantizableWeight")
struct QuantizableWeightTests {
    @Test("a transformer linear weight is packed, and its scales hang off the same base")
    func transformerLinear() throws {
        let weight = try #require(
            QuantizableWeight(
                name: "layers.0.attention.to_q.weight", shape: [3840, 3840], groupSize: 64))
        #expect(weight.base == "layers.0.attention.to_q")
        #expect(weight.outDim == 3840)
        #expect(weight.inDim == 3840)
        #expect(weight.weightKey == "layers.0.attention.to_q.weight")
        #expect(weight.scalesKey == "layers.0.attention.to_q.scales")
        #expect(weight.biasesKey == "layers.0.attention.to_q.biases")
    }

    @Test("a text encoder projection is packed")
    func textEncoderProjection() throws {
        let weight = try #require(
            QuantizableWeight(
                name: "model.layers.0.mlp.down_proj.weight", shape: [2560, 9728], groupSize: 64))
        #expect(weight.base == "model.layers.0.mlp.down_proj")
        #expect(weight.inDim == 9728)
    }

    @Test("the adaLN modulation inside a block is packed, unlike the final layer's")
    func adaLNModulation() {
        #expect(
            QuantizableWeight(
                name: "layers.0.adaLN_modulation.0.weight", shape: [15360, 256], groupSize: 64)
                != nil)
        #expect(
            QuantizableWeight(
                name: "all_final_layer.2-1.adaLN_modulation.1.weight",
                shape: [3840, 256],
                groupSize: 64
            ) == nil)
    }

    @Test("norms, embeddings, biases, and one-dimensional tensors are left alone")
    func passthroughTensors() {
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
            #expect(
                QuantizableWeight(name: name, shape: shape, groupSize: 64) == nil,
                "\(name) should not be packed")
        }
    }

    @Test("a weight the group size does not divide stays full precision")
    func indivisibleInputDimension() {
        // 96 columns: three groups of 32, but not a whole number of 64s. Every input width in
        // Z-Image happens to divide by 128, so the packed set is the same at any group size,
        // but the rule still has to hold or a future model would silently lose layers.
        #expect(QuantizableWeight(name: "a.weight", shape: [64, 96], groupSize: 64) == nil)
        #expect(QuantizableWeight(name: "a.weight", shape: [64, 96], groupSize: 32) != nil)
        #expect(QuantizableWeight(name: "a.weight", shape: [64, 100], groupSize: 32) == nil)
    }
}

@Suite("QuantizationPrecision")
struct QuantizationPrecisionTests {
    @Test("MLX only packs four or eight bits into groups of 32, 64, or 128")
    func rejectsUnsupportedSettings() {
        #expect(throws: QuantizationError.unsupportedBits(6)) {
            try QuantizationPrecision(bits: 6, groupSize: 64)
        }
        #expect(throws: QuantizationError.unsupportedGroupSize(48)) {
            try QuantizationPrecision(bits: 4, groupSize: 48)
        }
    }

    @Test("the group's float32 scale and bias are counted in the cost of a weight")
    func bitsPerWeight() throws {
        #expect(try QuantizationPrecision(bits: 4, groupSize: 64).bitsPerWeight == 5)
        #expect(try QuantizationPrecision(bits: 4, groupSize: 32).bitsPerWeight == 6)
        #expect(try QuantizationPrecision(bits: 8, groupSize: 32).bitsPerWeight == 10)
    }

    @Test("a recipe can keep the text encoder at a different precision")
    func mixedRecipe() throws {
        let uniform = try QuantizationRecipe(bits: 4, groupSize: 64)
        #expect(uniform.isUniform)
        #expect(uniform.precision(for: .transformer) == uniform.precision(for: .textEncoder))

        let mixed = QuantizationRecipe(
            transformer: try QuantizationPrecision(bits: 4, groupSize: 64),
            textEncoder: try QuantizationPrecision(bits: 8, groupSize: 32)
        )
        #expect(!mixed.isUniform)
        #expect(mixed.precision(for: .textEncoder).bits == 8)
    }
}
