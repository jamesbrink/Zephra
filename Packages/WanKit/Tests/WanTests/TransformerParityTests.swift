import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import Wan

@Suite("the transformer reproduces the reference, block and whole")
struct TransformerParityTests {
    /// The doll's house the fixtures were dumped at: two heads of twelve, eight latent
    /// channels, a sixteen-wide text stream, two blocks.
    static let configuration = WanTransformerConfiguration(
        numAttentionHeads: 2, attentionHeadDim: 12, inChannels: 8, outChannels: 8,
        textDim: 16, freqDim: 32, ffnDim: 32, numLayers: 2, ropeMaxSeqLen: 32)

    static func loaded(_ fixture: [String: MLXArray]) throws -> WanTransformer {
        let model = WanTransformer(configuration)
        try PackedWeightLoading.load(
            into: model,
            weights: WanTransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        return model
    }

    @Test("one block returns the reference's stream on a per-token modulation")
    func block() throws {
        let fixture = try Fixture.load("transformer_block")
        let block = WanTransformerBlock(Self.configuration)
        try PackedWeightLoading.load(
            into: block,
            weights: WanTransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        let table = WanTransformer(Self.configuration).rotaryTable(frames: 3, height: 2, width: 2)
        let output = block(
            try #require(fixture["in.hidden_states"]),
            text: try #require(fixture["in.encoder_hidden_states"]),
            modulation: try #require(fixture["in.temb"]),
            rotary: table)
        let expected = try #require(fixture["out.hidden_states"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test("the whole model returns the reference's velocity on a scalar timestep")
    func model() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try Self.loaded(fixture)
        // One eval per block, so the resident loop's flush is exercised at doll's-house size.
        model.blocksPerEval = 1
        let output = try model(
            latent: try #require(fixture["in.hidden_states"]),
            text: try #require(fixture["in.encoder_hidden_states"]),
            timesteps: try #require(fixture["in.timestep"]))
        let expected = try #require(fixture["out.hidden_states"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test("the patch kernel is turned round from the checkpoint's order at load")
    func patchKernel() throws {
        let fixture = try Fixture.load("transformer_model")
        let stored = try #require(fixture["model.patch_embedding.weight"])
        #expect(stored.shape == [24, 8, 1, 2, 2])
        let model = try Self.loaded(fixture)
        #expect(model.patchEmbedding.weight.shape == [24, 1, 2, 2, 8])
        // A kernel already in MLX's order is left alone.
        let sanitized = WanTransformerWeights.sanitized(["patch_embedding.weight": model.patchEmbedding.weight])
        #expect(sanitized["patch_embedding.weight"]?.shape == [24, 1, 2, 2, 8])
    }

    @Test("a bfloat16 latent runs the stream in bfloat16 and lands near the reference")
    func precision() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try Self.loaded(fixture)
        PackedWeightLoading.castFloatParameters(of: model, to: .bfloat16)
        let output = try model(
            latent: try #require(fixture["in.hidden_states"]).asType(.bfloat16),
            text: try #require(fixture["in.encoder_hidden_states"]),
            timesteps: try #require(fixture["in.timestep"]))
        #expect(output.dtype == .bfloat16)
        #expect(Fixture.maxAbsoluteDifference(output, try #require(fixture["out.hidden_states"])) < 0.5)
    }
}
