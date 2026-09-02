import Foundation
import Testing

@testable import ZephraQuantization

/// The mechanical half of the decision: what MLX's affine quantization is able to pack at all.
/// Whether a given model *wants* a tensor packed is its plan's business, and is pinned beside
/// that plan.
@Suite("QuantizableWeight")
struct QuantizableWeightTests {
    @Test("a two-dimensional weight is packable, and its scales hang off the same base")
    func twoDimensionalWeight() throws {
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

    @Test("only a two-dimensional tensor named .weight can be packed")
    func shapeAndSuffix() {
        #expect(QuantizableWeight(name: "a.weight", shape: [3840], groupSize: 64) == nil)
        #expect(QuantizableWeight(name: "a.weight", shape: [4, 64, 64], groupSize: 64) == nil)
        #expect(QuantizableWeight(name: "a.bias", shape: [64, 64], groupSize: 64) == nil)
        #expect(QuantizableWeight(name: "x_pad_token", shape: [1, 3840], groupSize: 64) == nil)
    }

    @Test("a weight the group size does not divide stays full precision")
    func indivisibleInputDimension() {
        // 96 columns: three groups of 32, but not a whole number of 64s. This is why precision
        // is resolved before this check runs — the group size being tested against is the one
        // the plan chose for that tensor, not a single global.
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
}
