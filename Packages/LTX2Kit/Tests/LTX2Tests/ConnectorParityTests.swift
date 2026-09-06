import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

/// The video connector against diffusers' `LTX2ConnectorTransformer1d`, weights and all.
///
/// A two-block, 32-wide connector with four heads and four registers over twelve positions,
/// one prompt full and one with seven pads. What this pins: the registers landing behind the
/// front-aligned real tokens in absolute-position order, the 1-D split rotary embedding in the
/// reference's log-spaced ladder, the per-head gate read from the block's input, the q/k norms
/// spanning every head, and the affine-free norms on either side of the residuals.
@Suite("The text connector reproduces the reference's conditioning")
struct ConnectorParityTests {
    @Test("every position matches, registers included")
    func embeddingMatches() throws {
        let fixture = try Fixture.load("connector")
        let connector = try Self.loaded(fixture)
        let features = try #require(fixture["in.features"])
        let padding = try #require(fixture["in.attention_mask"])
        let reference = try #require(fixture["out.embedding"])

        let embedding = connector(features, padding: padding)

        #expect(embedding.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(embedding, reference)
        #expect(difference < 2e-4, Comment(rawValue: "conditioning differs by \(difference)"))
        // With registers in, nothing is masked downstream: the reference's mask is all ones.
        let mask = try #require(fixture["out.mask"])
        #expect(MLX.all(mask .== 1).item(Bool.self))
    }

    @Test("real tokens move to the front in order and the padding falls behind them")
    func frontAlignment() throws {
        let x = MLXArray(Array(0..<Int32(12))).reshaped(1, 12, 1)
        let padding = MLXArray([0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1] as [Int32]).reshaped(1, 12)
        let aligned = LTX2TextConnector.frontAligned(x, padding: padding).reshaped(12).asArray(Int32.self)
        #expect(aligned == [3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 1, 2])
    }

    @Test("the tree's tensors are exactly the video connector's, under their renamed positions")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("connector")
        let connector = LTX2TextConnector(dim: 32, heads: 4, layers: 2, registerCount: 4)
        let ours = Set(connector.parameters().flattened().map(\.0))
        let theirs = Set(LTX2ConnectorWeights.connectorWeights(fixture).keys)
        #expect(ours.subtracting(theirs).isEmpty, Comment(rawValue: "unfilled: \(ours.subtracting(theirs).sorted())"))
        #expect(theirs.subtracting(ours).isEmpty, Comment(rawValue: "unloaded: \(theirs.subtracting(ours).sorted())"))
        // And back again: a module path names the tensor the manifest and the stream know.
        #expect(
            LTX2ConnectorWeights.checkpointName(of: "transformer_1d_blocks.1.ff.input.weight")
                == "connector.video_embeddings_connector.transformer_1d_blocks.1.ff.net.0.proj.weight")
        #expect(
            LTX2ConnectorWeights.checkpointName(of: "transformer_1d_blocks.0.attn1.to_out.bias")
                == "connector.video_embeddings_connector.transformer_1d_blocks.0.attn1.to_out.0.bias")
    }

    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2TextConnector {
        let connector = LTX2TextConnector(dim: 32, heads: 4, layers: 2, registerCount: 4)
        try connector.update(
            parameters: ModuleParameters.unflattened(LTX2ConnectorWeights.connectorWeights(fixture)),
            verify: .all)
        MLX.eval(connector.parameters())
        return connector
    }
}
