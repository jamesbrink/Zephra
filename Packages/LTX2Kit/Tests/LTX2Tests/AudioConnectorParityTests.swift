import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import LTX2

/// The audio connector against diffusers' second `LTX2ConnectorTransformer1d`, and the audio
/// projection against its `audio_text_proj_in`: the same doll's house as the video pair at
/// half the width, one block, two heads.
@Suite("The audio connector reproduces the reference's audio conditioning")
struct AudioConnectorParityTests {
    @Test("the audio projection scales the stacked states by its own width's factor")
    func projectionMatches() throws {
        let fixture = try Fixture.load("audio_connector")
        let extractor = LTX2FeatureExtractor(hiddenSize: 32, stateCount: 7, outputSize: 16, modality: .audio)
        try PackedWeightLoading.load(
            into: extractor,
            weights: LTX2ConnectorWeights.projectionWeights(fixture, modality: .audio),
            manifest: nil)
        let states = try #require(fixture["in.hidden_states"])
        let stacked = (0..<7).map { states[.ellipsis, $0] }
        let features = extractor(stacked, padding: try #require(fixture["in.attention_mask"]))
        #expect(Fixture.maxAbsoluteDifference(features, try #require(fixture["in.features"])) < 1e-4)
    }

    @Test("every position of the audio embedding matches, registers included")
    func embeddingMatches() throws {
        let fixture = try Fixture.load("audio_connector")
        let connector = LTX2TextConnector(dim: 16, heads: 2, layers: 1, registerCount: 4)
        try PackedWeightLoading.load(
            into: connector,
            weights: LTX2ConnectorWeights.connectorWeights(fixture, modality: .audio),
            manifest: nil)
        let embedding = connector(try #require(fixture["in.features"]), padding: try #require(fixture["in.attention_mask"]))
        let reference = try #require(fixture["out.embedding"])
        #expect(embedding.shape == reference.shape)
        #expect(Fixture.maxAbsoluteDifference(embedding, reference) < 2e-4)
    }

    @Test("the audio lane's paths name the pack's audio tensors and nothing of the video's")
    func names() {
        #expect(
            LTX2ConnectorWeights.checkpointName(of: "transformer_1d_blocks.0.attn1.to_q.weight", modality: .audio)
                == "connector.audio_embeddings_connector.transformer_1d_blocks.0.attn1.to_q.weight")
        #expect(
            LTX2ConnectorWeights.projectionCheckpointName(of: "aggregate_embed.weight", modality: .audio)
                == "connector.text_embedding_projection.audio_aggregate_embed.weight")
        #expect(
            LTX2ConnectorWeights.projectionCheckpointName(of: "aggregate_embed.bias", modality: .video)
                == "connector.text_embedding_projection.video_aggregate_embed.bias")
        // The bare module path is what the loader asks the manifest about; a miss there
        // falls back to the manifest's default and builds the projection at four bits,
        // which is the wrong shape for the eight-bit tensor on disk.
        #expect(
            LTX2ConnectorWeights.projectionCheckpointName(of: "aggregate_embed", modality: .video)
                == "connector.text_embedding_projection.video_aggregate_embed")
        #expect(
            LTX2ConnectorWeights.projectionCheckpointName(of: "aggregate_embed", modality: .audio)
                == "connector.text_embedding_projection.audio_aggregate_embed")
    }
}
