import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

/// The Gemma 4 stack against `transformers`, weights and all, on two left-padded prompts.
///
/// The fixture is a six-layer, 32-wide stand-in with the real model's structure in miniature:
/// two sliding layers then a full one, twice; full layers with wider heads, one key-value head,
/// no value projection, and a quarter of each head rotated; randomised norms and layer scalars.
/// Every way this port could be wrong is structural, and structure shows at any width. Padded
/// positions are not compared: the reference leaves them undefined-but-finite and the connector
/// zeroes them.
@Suite("The Gemma 4 encoder reproduces the reference's hidden states")
struct TextEncoderParityTests {
    /// The doll's house, decoded the way the real config is read.
    static let configurationJSON = """
        {"text_config": {
          "hidden_size": 32, "num_hidden_layers": 6, "num_attention_heads": 4,
          "num_key_value_heads": 2, "head_dim": 8, "global_head_dim": 16,
          "num_global_key_value_heads": 1, "attention_k_eq_v": true,
          "layer_types": ["sliding_attention", "sliding_attention", "full_attention",
                          "sliding_attention", "sliding_attention", "full_attention"],
          "sliding_window": 4, "intermediate_size": 48, "vocab_size": 64,
          "rms_norm_eps": 1e-6, "pad_token_id": 0, "bos_token_id": 2,
          "rope_parameters": {
            "sliding_attention": {"rope_type": "default", "rope_theta": 10000.0},
            "full_attention": {"rope_type": "proportional", "rope_theta": 1000000.0,
                               "partial_rotary_factor": 0.25}
          }
        }}
        """

    @Test("all seven hidden states match at every real token, the last one normed")
    func hiddenStatesMatch() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Self.loaded(fixture)
        let tokens = try #require(fixture["in.input_ids"])
        let padding = try #require(fixture["in.attention_mask"])
        let reference = try #require(fixture["out.hidden_states"])

        let states = try model.hiddenStates(tokens, padding: padding)
        #expect(states.count == 7)
        #expect(reference.shape == [7, 2, 12, 32])

        // Row 0 is a full prompt; row 1 has five pads at the front, which are skipped.
        for (index, state) in states.enumerated() {
            let ours = state[0..., 0..., 0...]
            let theirs = reference[index]
            let full = Fixture.maxAbsoluteDifference(ours[0], theirs[0])
            let real = Fixture.maxAbsoluteDifference(ours[1, 5...], theirs[1, 5...])
            #expect(full < 2e-4, Comment(rawValue: "state \(index), row 0 differs by \(full)"))
            #expect(real < 2e-4, Comment(rawValue: "state \(index), row 1 differs by \(real)"))
        }
    }

    @Test("the tree's tensors are exactly the checkpoint's under its prefix")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = Gemma4TextModel(try Self.configuration())
        let ours = Set(model.parameters().flattened().map { Gemma4TextModel.checkpointPrefix + $0.0 })
        let theirs = Set(Self.checkpointWeights(fixture).keys)
        #expect(ours.subtracting(theirs).isEmpty, Comment(rawValue: "unfilled: \(ours.subtracting(theirs).sorted())"))
        #expect(theirs.subtracting(ours).isEmpty, Comment(rawValue: "unloaded: \(theirs.subtracting(ours).sorted())"))
        // The full layers carry no value projection, which is the shape `attention_k_eq_v` leaves.
        #expect(!theirs.contains("model.language_model.layers.2.self_attn.v_proj.weight"))
        #expect(theirs.contains("model.language_model.layers.1.self_attn.v_proj.weight"))
    }

    @Test("the sliding window is live: widening it moves a sliding layer's states")
    func slidingWindowIsLive() throws {
        let fixture = try Fixture.load("text_encoder")
        let narrow = try Self.loaded(fixture)
        let wide = try Self.loaded(fixture, slidingWindow: 64)
        let tokens = try #require(fixture["in.input_ids"])
        let padding = try #require(fixture["in.attention_mask"])
        let a = try narrow.hiddenStates(tokens, padding: padding)[1][0]
        let b = try wide.hiddenStates(tokens, padding: padding)[1][0]
        // The first four positions see everything either way; later ones lose keys to the window.
        #expect(Fixture.maxAbsoluteDifference(a[..<4], b[..<4]) < 1e-6)
        #expect(Fixture.maxAbsoluteDifference(a[4...], b[4...]) > 1e-4)
    }

    static func configuration(slidingWindow: Int = 4) throws -> Gemma4Configuration {
        let json = configurationJSON.replacingOccurrences(
            of: "\"sliding_window\": 4", with: "\"sliding_window\": \(slidingWindow)")
        let file = try JSONDecoder().decode(Gemma4Configuration.File.self, from: Data(json.utf8))
        return try Gemma4Configuration(file.textConfig)
    }

    /// The fixture's checkpoint tensors, prefix and all.
    static func checkpointWeights(_ fixture: [String: MLXArray]) -> [String: MLXArray] {
        Fixture.weights(fixture, under: "text_encoder.")
    }

    /// A model with the fixture's weights in it.
    static func loaded(_ fixture: [String: MLXArray], slidingWindow: Int = 4) throws -> Gemma4TextModel {
        let model = Gemma4TextModel(try configuration(slidingWindow: slidingWindow))
        let prefix = Gemma4TextModel.checkpointPrefix
        let weights = checkpointWeights(fixture).reduce(into: [String: MLXArray]()) { stripped, entry in
            stripped[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
        try model.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        MLX.eval(model.parameters())
        return model
    }
}
