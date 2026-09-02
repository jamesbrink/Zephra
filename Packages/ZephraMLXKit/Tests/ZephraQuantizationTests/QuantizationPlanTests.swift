import Foundation
import Testing

@testable import ZephraQuantization

/// How a plan decides what happens to one tensor: the first rule that matches wins, a rule with
/// no precision means leave the tensor alone, and anything no rule claims falls to the
/// component's own precision.
@Suite("Quantization plan")
struct QuantizationPlanTests {
    private static let fourBit = try! QuantizationPrecision(bits: 4, groupSize: 64)
    private static let eightBit = try! QuantizationPrecision(bits: 8, groupSize: 64)

    @Test("a pattern matches at the front, at the back, and anywhere inside")
    func patternsMatchWhereTheySay() {
        #expect(NamePattern.prefix("all_final").matches("all_final_layer.2-1.weight"))
        #expect(!NamePattern.prefix("final").matches("all_final_layer.2-1.weight"))
        #expect(NamePattern.suffix(".weight").matches("blocks.0.to_q.weight"))
        #expect(NamePattern.contains("img_mod").matches("blocks.7.img_mod.1.weight"))
        #expect(!NamePattern.contains("img_mod").matches("blocks.7.txt_mod.1.weight"))
    }

    @Test("the first matching rule wins, so narrow rules go first")
    func firstMatchWins() {
        let component = QuantizedComponent(
            directoryName: "transformer",
            rules: [
                WeightPrecisionRule(.contains("img_mod"), precision: Self.eightBit),
                WeightPrecisionRule(.contains("blocks"), precision: Self.fourBit),
            ],
            fallback: nil
        )
        #expect(component.precision(for: "blocks.7.img_mod.1.weight")?.bits == 8)
        #expect(component.precision(for: "blocks.7.to_q.weight")?.bits == 4)
        #expect(component.precision(for: "proj_out.weight") == nil)
    }

    @Test("a rule with no precision excludes the tensor, even inside a packed component")
    func aSkipIsARuleWithNoPrecision() {
        let component = QuantizedComponent(
            directoryName: "transformer",
            rules: WeightPrecisionRule.normsAndEmbeddings,
            fallback: Self.fourBit
        )
        #expect(component.precision(for: "layers.0.attention_norm1.weight") == nil)
        #expect(component.precision(for: "model.embed_tokens.weight") == nil)
        #expect(component.precision(for: "model.layers.0.input_layernorm.weight") == nil)
        #expect(component.precision(for: "layers.0.attention.to_q.weight")?.bits == 4)
    }

    @Test("a plan is uniform only when every packed tensor shares one precision")
    func uniformity() {
        let plain = QuantizationPlan(
            components: [QuantizedComponent(directoryName: "transformer", fallback: Self.fourBit)],
            verbatimDirectories: []
        )
        #expect(plain.isUniform)

        let mixed = QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: [WeightPrecisionRule(.contains("img_mod"), precision: Self.eightBit)],
                    fallback: Self.fourBit
                )
            ],
            verbatimDirectories: []
        )
        #expect(!mixed.isUniform)
        // Excluding tensors is not mixing precisions: nothing is packed two ways.
        let excluding = QuantizationPlan(
            components: [
                QuantizedComponent(
                    directoryName: "transformer",
                    rules: WeightPrecisionRule.normsAndEmbeddings,
                    fallback: Self.fourBit
                )
            ],
            verbatimDirectories: []
        )
        #expect(excluding.isUniform)
    }
}
