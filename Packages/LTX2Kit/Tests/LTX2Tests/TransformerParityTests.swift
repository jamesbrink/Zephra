import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import LTX2

@Suite("the transformer reproduces the reference, block and whole")
struct TransformerParityTests {
    /// The doll's house the fixtures were dumped at: two heads of sixteen, eight latent
    /// channels, a text stream as wide as the model's, two blocks.
    static let configuration = LTX2TransformerConfiguration(
        inChannels: 8, outChannels: 8, heads: 2, headDim: 16, crossAttentionDim: 32, layers: 2)
    /// Three latent frames of two by four cells, at 24 frames per second.
    static let layout = LTX2LatentLayout(frames: 3, height: 2, width: 4)

    @Test("one block returns the reference's video stream with the audio lane absent")
    func block() throws {
        let fixture = try Fixture.load("transformer_block")
        let block = LTX2Block(Self.configuration)
        try PackedWeightLoading.load(
            into: block,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        let rotary = LTX2Transformer(Self.configuration).rotary
        let output = block(
            try #require(fixture["in.hidden"]),
            text: try #require(fixture["in.text"]),
            conditioning: LTX2BlockConditioning(
                modulation: try #require(fixture["in.modulation"]),
                prompt: try #require(fixture["in.prompt"])),
            rotary: rotary.table(positions: Self.layout.positions(frameRate: 24)))
        let expected = try #require(fixture["out.hidden"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test("the whole model returns the reference's velocity, first frame marked")
    func model() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = LTX2Transformer(Self.configuration)
        try PackedWeightLoading.load(
            into: model,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        // One eval per block, so the resident loop's flush is exercised at doll's-house size.
        model.blocksPerEval = 1
        let output = try model(
            tokens: try #require(fixture["in.tokens"]),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: Self.layout,
            frameRate: 24)
        let expected = try #require(fixture["out.tokens"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test("float32 tables do not widen a bfloat16 stream")
    func precision() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = LTX2Transformer(Self.configuration)
        try PackedWeightLoading.load(
            into: model,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        // What a load does, then the tables put back to the float32 the pack ships them in: a
        // loader that misses them, or a stream handing back raw nodes, must still not widen
        // every activation after the first block.
        PackedWeightLoading.castFloatParameters(of: model, to: .bfloat16)
        let tables = model.parameters().flattened().filter { $0.0.hasSuffix("scale_shift_table") }
        model.update(parameters: ModuleParameters.unflattened(
            Dictionary(uniqueKeysWithValues: tables.map { ($0.0, $0.1.asType(.float32)) })))
        let output = try model(
            tokens: try #require(fixture["in.tokens"]).asType(.bfloat16),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: Self.layout,
            frameRate: 24)
        #expect(output.dtype == .bfloat16)
        #expect(Fixture.maxAbsoluteDifference(output, try #require(fixture["out.tokens"])) < 0.1)
    }
}
