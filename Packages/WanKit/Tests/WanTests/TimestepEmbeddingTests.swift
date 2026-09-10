import Foundation
import MLX
import Testing
import ZephraMLX

@testable import Wan

@Suite("the condition embedder reproduces the reference's timestep rows and projected text")
struct TimestepEmbeddingTests {
    static func loaded(_ fixture: [String: MLXArray]) throws -> WanConditionEmbedder {
        let embedder = WanConditionEmbedder(TransformerParityTests.configuration)
        try PackedWeightLoading.load(
            into: embedder,
            weights: WanTransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        return embedder
    }

    @Test("a scalar timestep gives the reference's embedding, six rows and text")
    func scalar() throws {
        let fixture = try Fixture.load("timestep")
        let embedder = try Self.loaded(fixture)
        let (embedded, modulation, text) = embedder(
            try #require(fixture["in.timestep"]), text: try #require(fixture["in.text"]), dtype: .float32)
        #expect(embedded.shape == [1, 24])
        #expect(modulation.shape == [1, 6, 24])
        #expect(Fixture.maxAbsoluteDifference(embedded, try #require(fixture["out.temb"])) < 1e-4)
        #expect(
            Fixture.maxAbsoluteDifference(modulation, try #require(fixture["out.timestep_proj"]).reshaped([1, 6, 24]))
                < 1e-4)
        #expect(Fixture.maxAbsoluteDifference(text, try #require(fixture["out.encoder_hidden_states"])) < 1e-4)
    }

    @Test("a per-token timestep gives the reference's rows for every token through the field")
    func perToken() throws {
        let fixture = try Fixture.load("timestep")
        let embedder = try Self.loaded(fixture)
        let field = WanTimestepField(try #require(fixture["in.timestep_tokens"]))
        #expect(field.values.shape == [2])
        #expect(field.index.shape == [1, 12])
        let (embedded, modulation, _) = embedder(field.values, text: try #require(fixture["in.text"]), dtype: .float32)
        let perToken = field.perToken(modulation)
        #expect(perToken.shape == [1, 12, 6, 24])
        let expected = try #require(fixture["out.timestep_proj_tokens"]).reshaped([1, 12, 6, 24])
        #expect(Fixture.maxAbsoluteDifference(perToken, expected) < 1e-4)
        #expect(
            Fixture.maxAbsoluteDifference(field.perToken(embedded), try #require(fixture["out.temb_tokens"])) < 1e-4)
    }

    @Test("a field with one timestep everywhere collapses to a broadcast row")
    func uniformField() {
        let field = WanTimestepField(MLXArray([757, 757, 757, 757] as [Float]).reshaped([2, 2]))
        #expect(field.values.asArray(Float.self) == [757])
        #expect(field.index.shape == [2, 1])
        let scalar = WanTimestepField(MLXArray([1000, 522] as [Float]))
        #expect(scalar.values.asArray(Float.self) == [1000, 522])
        #expect(scalar.index.shape == [2, 1])
        #expect(scalar.index.asArray(Int32.self) == [0, 1])
    }

    @Test("the sinusoid is cosines first, in the model's own units")
    func sinusoid() {
        let embedding = WanTimestepEmbedding(frequencyChannels: 32, embeddingDim: 8)
        let projected = embedding.sinusoid(MLXArray([757] as [Float])).asArray(Float.self)
        #expect(projected.count == 32)
        #expect(abs(projected[0] - Foundation.cos(Float(757))) < 1e-3)
        #expect(abs(projected[16] - Foundation.sin(Float(757))) < 1e-3)
        #expect(embedding.ladder[1] == Float(Foundation.exp(-Foundation.log(10000.0) / 16)))
    }
}
