import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import Wan

/// The UMT5 encoder against `transformers`, weights and all, on one full and one padded prompt.
///
/// The fixture is a two-layer, 32-wide stand-in with the real model's structure in miniature:
/// a bias table in every layer, unscaled logits, scale-only norms, the gated tanh GELU, with
/// the norms and the bias tables randomised. Every way this port could be wrong is structural,
/// and structure shows at any width. Padded positions are compared too: the reference
/// computes them from the real keys alone, and so does the port.
@Suite("The UMT5 encoder reproduces the reference's last hidden state")
struct TextEncoderParityTests {
    /// The doll's house, in the numbers `dump_text_encoder.py` built it with.
    static let configuration = UMT5Configuration(
        dModel: 32, dKV: 8, numHeads: 4, dFF: 48, numLayers: 2,
        relativeAttentionNumBuckets: 8, relativeAttentionMaxDistance: 16,
        layerNormEpsilon: 1e-6, vocabSize: 64)

    @Test("the last hidden state matches at every position of both rows")
    func lastHiddenStateMatches() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Self.loaded(fixture)
        let tokens = try #require(fixture["in.input_ids"])
        let padding = try #require(fixture["in.attention_mask"])
        let reference = try #require(fixture["out.last_hidden_state"])

        let ours = try model.lastHiddenState(tokens, padding: padding)
        #expect(ours.shape == [2, 12, 32])
        let difference = Fixture.maxAbsoluteDifference(ours, reference)
        #expect(difference < 1e-4, Comment(rawValue: "differs by \(difference)"))
    }

    @Test("layer 0's position bias is the reference's, which pins the bucket function")
    func positionBiasMatches() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Self.loaded(fixture)
        let reference = try #require(fixture["out.position_bias"])
        let buckets = UMT5RelativePositionBucket.table(length: 12, buckets: 8, maxDistance: 16)
        let ours = model.layers[0].layer.0.attention.positionBias(buckets: buckets)
        #expect(ours.shape == [1, 4, 12, 12])
        #expect(Fixture.maxAbsoluteDifference(ours, reference) < 1e-6)
    }

    @Test("the real model's buckets match the reference at every distance a prompt can hold")
    func realBucketsMatch() throws {
        let fixture = try Fixture.load("text_encoder")
        let positions = try #require(fixture["in.bucket_relative_positions"]).asArray(Int32.self)
        let reference = try #require(fixture["out.buckets"]).asArray(Int32.self)
        let ours = positions.map {
            Int32(UMT5RelativePositionBucket.bucket(of: Int($0), buckets: 32, maxDistance: 128))
        }
        #expect(ours == reference)
        // 31, not 32: the forward half starts at distance 1, so its "distance 0" bucket is
        // never gathered, and the table's row for it is dead weight in every layer.
        #expect(Set(ours).count == 31)
    }

    @Test("the tree's tensors are exactly the checkpoint's, `shared.weight` included")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = UMT5TextEncoder(Self.configuration)
        let ours = Set(model.parameters().flattened().map(\.0))
        let theirs = Set(Self.checkpointWeights(fixture).keys)
        #expect(ours.subtracting(theirs).isEmpty, Comment(rawValue: "unfilled: \(ours.subtracting(theirs).sorted())"))
        #expect(theirs.subtracting(ours).isEmpty, Comment(rawValue: "unloaded: \(theirs.subtracting(ours).sorted())"))
        #expect(theirs.contains("shared.weight"))
        #expect(theirs.contains("encoder.block.1.layer.0.SelfAttention.relative_attention_bias.weight"))
        #expect(!theirs.contains("encoder.embed_tokens.weight"))
    }

    @Test("streaming the blocks from the fixture file gives the resident result")
    func streamedMatchesResident() throws {
        let fixture = try Fixture.load("text_encoder")
        let resident = try Self.loaded(fixture)
        let streamed = try Self.loaded(fixture)
        let file = try #require(Bundle.module.resourceURL?.appending(path: "Fixtures/text_encoder.safetensors"))
        streamed.stream = try LayerWeightStream(
            layers: streamed.layers,
            keyPrefix: UMT5TextEncoder.blocksKeyPrefix,
            index: ShardIndex(shards: [file]),
            depth: 1,
            checkpointName: { "text_encoder." + $0 })
        let tokens = try #require(fixture["in.input_ids"])
        let padding = try #require(fixture["in.attention_mask"])
        let a = try resident.lastHiddenState(tokens, padding: padding)
        // Two passes, so the second reads the nodes the first pass handed back.
        _ = try streamed.lastHiddenState(tokens, padding: padding)
        let b = try streamed.lastHiddenState(tokens, padding: padding)
        #expect(Fixture.maxAbsoluteDifference(a, b) < 1e-6)
    }

    /// The fixture's checkpoint tensors, under the names the release uses.
    static func checkpointWeights(_ fixture: [String: MLXArray]) -> [String: MLXArray] {
        Fixture.weights(fixture, under: "text_encoder.")
    }

    /// A model with the fixture's weights in it.
    static func loaded(_ fixture: [String: MLXArray]) throws -> UMT5TextEncoder {
        let model = UMT5TextEncoder(configuration)
        try model.update(parameters: ModuleParameters.unflattened(checkpointWeights(fixture)), verify: .all)
        MLX.eval(model.parameters())
        return model
    }
}
