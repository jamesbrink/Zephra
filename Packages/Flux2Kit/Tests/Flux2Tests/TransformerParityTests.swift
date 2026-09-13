import Foundation
import MLX
import Testing
import ZephraMLX

@testable import Flux2

@Suite("The transformer reproduces the reference block by block")
struct TransformerParityTests {
    /// The doll's house the fixtures were dumped at: two heads of sixteen, so the four rotary
    /// axes of four each fill one head exactly.
    static let configurationJSON = """
        {"attention_head_dim": 16, "axes_dims_rope": [4, 4, 4, 4], "eps": 1e-6,
         "guidance_embeds": false, "in_channels": 8, "joint_attention_dim": 24,
         "mlp_ratio": 3.0, "num_attention_heads": 2, "num_layers": 2, "num_single_layers": 2,
         "out_channels": 8, "rope_theta": 2000, "timestep_guidance_channels": 256}
        """

    static func configuration() throws -> Flux2TransformerConfiguration {
        try JSONDecoder()
            .decode(Flux2TransformerConfiguration.self, from: Data(configurationJSON.utf8))
            .validated()
    }

    /// The rotary table the dump built over text positions followed by a 3x4 image grid.
    static func frequencies(_ fixture: [String: MLXArray], under prefix: String) throws
        -> RotaryFrequencies
    {
        RotaryFrequencies(
            cos: try #require(fixture["\(prefix)in.cos"]),
            sin: try #require(fixture["\(prefix)in.sin"]))
    }

    @Test("a dual-stream block returns the reference's image and text streams")
    func dualStreamBlock() throws {
        let fixture = try Fixture.load("transformer_block")
        let configuration = try Self.configuration()
        let block = Flux2DoubleBlock(
            dim: configuration.innerDim,
            heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim,
            mlpHidden: configuration.mlpDim,
            eps: configuration.eps)

        // The dump is one bare block, so its key has no `transformer_blocks.` prefix for
        // `Flux2TransformerWeights` to match on. The whole-model test is what pins that rename.
        let weights = Fixture.weights(fixture, under: "block.").reduce(into: [String: MLXArray]()) {
            renamed, entry in
            renamed[entry.key.replacingOccurrences(of: "attn.to_out.0.", with: "attn.to_out.")] =
                entry.value
        }
        try PackedWeightLoading.load(into: block, weights: weights, manifest: nil)

        let (image, text) = block(
            image: try #require(fixture["block.in.image"]),
            text: try #require(fixture["block.in.text"]),
            imageModulation: Flux2SharedModulation.split(
                try #require(fixture["block.in.modulation_image"]), sets: 2),
            textModulation: Flux2SharedModulation.split(
                try #require(fixture["block.in.modulation_text"]), sets: 2),
            frequencies: try Self.frequencies(fixture, under: "block."))

        let expectedImage = try #require(fixture["block.out.image"])
        let expectedText = try #require(fixture["block.out.text"])
        #expect(Fixture.maxAbsoluteDifference(image, expectedImage) < 1e-4)
        #expect(Fixture.maxAbsoluteDifference(text, expectedText) < 1e-4)
    }

    @Test("a single-stream block returns the reference's joined stream")
    func singleStreamBlock() throws {
        let fixture = try Fixture.load("transformer_single")
        let configuration = try Self.configuration()
        let block = Flux2SingleBlock(
            dim: configuration.innerDim,
            heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim,
            mlpHidden: configuration.mlpDim,
            eps: configuration.eps)
        try PackedWeightLoading.load(
            into: block, weights: Fixture.weights(fixture, under: "single."), manifest: nil)

        let hidden = block(
            try #require(fixture["single.in.hidden"]),
            modulation: Flux2SharedModulation.split(
                try #require(fixture["single.in.modulation"]), sets: 1)[0],
            frequencies: try Self.frequencies(fixture, under: "single."))

        let expected = try #require(fixture["single.out.hidden"])
        #expect(Fixture.maxAbsoluteDifference(hidden, expected) < 1e-4)
    }

    /// The blocks above agree with the reference to about 7e-7. This one lands near 7e-5, and
    /// the whole of the difference is the timestep sinusoid: fifteen of the frequency ladder's
    /// 128 entries land one float32 unit in the last place away from `torch.exp`, the timestep
    /// multiplies them by up to 1000, and every modulated layer downstream carries it. See
    /// `Flux2TimestepEmbedding.ladder`, which already rounds a double `exp` once to get this
    /// far. The margin under the tolerance is real but thin; a change that pushes it over is
    /// far more likely to be a bug than more of this.
    @Test("the whole model predicts the reference's velocity")
    func wholeModel() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = Flux2Transformer(try Self.configuration())
        try PackedWeightLoading.load(
            into: model,
            weights: Flux2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)

        let text = try #require(fixture["model.in.text"])
        let prediction = try model(
            latents: try #require(fixture["model.in.latents"]),
            text: text,
            timestep: try #require(fixture["model.in.timestep"]),
            frequencies: try Self.frequencies(fixture, under: "model."),
            textLength: text.shape[1])

        let expected = try #require(fixture["model.out.prediction"])
        #expect(prediction.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(prediction, expected) < 1e-4)
    }

    @Test("every checkpoint tensor lands somewhere, and every parameter is filled")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = Flux2Transformer(try Self.configuration())
        let wanted = Set(model.parameters().flattened().map(\.0))
        let supplied = Set(
            Flux2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")).keys)

        let missing = wanted.subtracting(supplied).sorted()
        let extra = supplied.subtracting(wanted).sorted()
        #expect(missing.isEmpty, Comment(rawValue: "no weight for \(missing)"))
        #expect(extra.isEmpty, Comment(rawValue: "no home for \(extra)"))
    }
}
