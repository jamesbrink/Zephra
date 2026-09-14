import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX
import ZephraTestSupport

@testable import Wan

@Suite("the transformer takes a per-token timestep the way the reference conditions on a first frame")
struct TransformerConditionedParityTests {
    @Test("the first frame's tokens at 0 and the rest at 757 reproduce the reference")
    func conditionedForward() throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let model = try TransformerParityTests.loaded(fixture)
        let timesteps = try #require(fixture["in.timestep"])
        #expect(timesteps.shape == [1, 12])
        let output = try model(
            latent: try #require(fixture["in.hidden_states"]),
            text: try #require(fixture["in.encoder_hidden_states"]),
            timesteps: timesteps)
        let expected = try #require(fixture["out.hidden_states"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test("a per-token field is not the same answer as the scalar it mostly holds")
    func conditioningChangesTheAnswer() throws {
        let plain = try Fixture.load("transformer_model")
        let conditioned = try Fixture.load("transformer_conditioned")
        #expect(
            Fixture.maxAbsoluteDifference(
                try #require(plain["out.hidden_states"]), try #require(conditioned["out.hidden_states"])) > 1e-2)
    }

    @Test("a field holding one timestep everywhere answers what the scalar answers")
    func uniformFieldIsTheScalar() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerParityTests.loaded(fixture)
        let latent = try #require(fixture["in.hidden_states"])
        let text = try #require(fixture["in.encoder_hidden_states"])
        let scalar = try model(latent: latent, text: text, timesteps: try #require(fixture["in.timestep"]))
        let field = try model(latent: latent, text: text, timesteps: MLX.full([1, 12], values: MLXArray(Float(757))))
        #expect(Fixture.maxAbsoluteDifference(scalar, field) < 1e-5)
    }

    @Test("the blocks stream from disk to the same answer as resident weights")
    func streamed() throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let model = try TransformerParityTests.loaded(fixture)
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        // The blocks' tensors under the checkpoint's names, as a shard the stream can read.
        let blocks = Fixture.weights(fixture, under: "model.").filter { $0.key.hasPrefix("blocks.") }
        try MLX.save(arrays: blocks, url: scratch.make("shards/model.safetensors"))
        let index = try ShardIndex(directory: scratch.url("shards"))
        model.stream = try LayerWeightStream(
            layers: model.blocks, keyPrefix: "blocks", index: index, depth: 1,
            checkpointName: WanTransformerWeights.checkpointName(of:))
        let expected = try #require(fixture["out.hidden_states"])
        for _ in 0..<2 {
            let output = try model(
                latent: try #require(fixture["in.hidden_states"]),
                text: try #require(fixture["in.encoder_hidden_states"]),
                timesteps: try #require(fixture["in.timestep"]))
            #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
        }
        #expect(model.stream?.lastPass?.bytes == model.stream?.bytesPerPass)
    }
}
