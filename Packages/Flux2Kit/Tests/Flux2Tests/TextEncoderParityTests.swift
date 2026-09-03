import Foundation
import MLX
import MLXNN
import Testing

@testable import Flux2

/// The Qwen3 encoder against the reference, weights and all.
///
/// The fixture is an eight-layer, 64-wide stand-in tapped at 2, 4, and 6, which is the right
/// size: every way this port could be wrong is structural, and structure shows at any width.
/// What it pins is the set of mistakes that compile perfectly and produce a different model --
/// the per-head query and key norms and where in the reshape they land, the bias-free
/// projections, how the taps are laid side by side, and whether the padding is actually masked.
///
/// Eight layers to reach a tap at six, in the same proportion as the published 36 tapped at 27,
/// because the reference norms only its last hidden state. Tapping the last layer of a stack
/// would compare against a norm this port has no reason to build.
@Suite("The Qwen3 encoder reproduces the reference's tapped hidden states")
struct TextEncoderParityTests {
    /// The doll's house, decoded rather than constructed because the configuration has no
    /// memberwise initialiser: it exists to be read out of a published `config.json`.
    private static let configurationJSON = """
        {
          "hidden_size": 64,
          "num_hidden_layers": 8,
          "num_attention_heads": 4,
          "num_key_value_heads": 2,
          "head_dim": 16,
          "intermediate_size": 128,
          "rms_norm_eps": 1e-6,
          "rope_theta": 1000000.0,
          "vocab_size": 100
        }
        """

    /// Where the fixture taps. The published configuration says `[9, 18, 27]`, which this small
    /// a stack cannot reach, so the encoder takes the taps as a parameter and the default stays
    /// the pipeline's.
    private static let taps = [2, 4, 6]

    @Test("the taps arrive concatenated the way the pipeline stacks and permutes them")
    func matchesTheReferenceConcatenation() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = try Self.loaded(fixture)
        let tokens = try #require(fixture["input_ids"])
        let reference = try #require(fixture["taps_concat"])

        let conditioning = encoder(tokens, validCount: 7)

        #expect(conditioning.shape == [1, 12, 192])
        #expect(reference.shape == [1, 12, 192])
        let difference = Fixture.maxAbsoluteDifference(conditioning, reference)
        #expect(difference < 2e-4, Comment(rawValue: "conditioning differs by \(difference)"))
    }

    @Test("tap n is the running hidden state after n layers, counting the embedding as zero")
    func eachTapMatchesItsHiddenState() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = try Self.loaded(fixture)
        let tokens = try #require(fixture["input_ids"])

        // Tap 0 is in here on purpose: it is the claim that the reference's `hidden_states[0]`
        // is the embedding output and not the first layer's, which is the off-by-one that would
        // shift every tap by a layer and still produce a plausible image.
        let wanted = [0] + Self.taps
        let states = encoder.model.hiddenStates(tokens, validCount: 7, taps: wanted)

        for (tap, state) in zip(wanted, states) {
            let reference = try #require(fixture["hidden_states.\(tap)"])
            let difference = Fixture.maxAbsoluteDifference(state, reference)
            #expect(difference < 2e-4, Comment(rawValue: "tap \(tap) differs by \(difference)"))
        }
    }

    @Test("the stack's tensors are the checkpoint's, less the layers and norm it never runs")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = Qwen3TextEncoder(try Self.configuration(), taps: Self.taps)

        let ours = Set(encoder.parameters().flattened().map(\.0))
        let expected = Set(Self.encoderWeights(fixture, layers: 6).keys)
        #expect(ours.subtracting(expected).isEmpty, Comment(rawValue: "unfilled: \(ours.subtracting(expected).sorted())"))
        #expect(expected.subtracting(ours).isEmpty, Comment(rawValue: "unloaded: \(expected.subtracting(ours).sorted())"))

        // What is left over is exactly what a tapped stack has no use for: the final norm, and
        // every layer past the deepest tap. The same two things, at the same proportions, that
        // leave 100 of the published checkpoint's 398 tensors on disk.
        let leftover = Set(fixture.keys.filter { $0.hasPrefix("model.") }).subtracting(expected)
        let unreached = Set(
            ["model.norm.weight"] + (6..<8).flatMap { WeightKeyCoverageTests.textEncoderLayerKeys($0) })
        #expect(leftover == unreached, Comment(rawValue: "leftover: \(leftover.sorted())"))
    }

    @Test("the padding mask is live: hiding the pad ids changes the states that see them")
    func thePaddingMaskIsLive() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = try Self.loaded(fixture)
        let tokens = try #require(fixture["input_ids"])

        let masked = encoder(tokens, validCount: 7)
        let unmasked = encoder(tokens, validCount: 12)

        // The real prefix cannot tell the difference: causality already hides everything after
        // it. Only the padded positions, which klein still feeds to the transformer, move.
        let prefix = Fixture.maxAbsoluteDifference(masked[0..., ..<7], unmasked[0..., ..<7])
        #expect(prefix < 1e-6, Comment(rawValue: "the prefix moved by \(prefix)"))
        let padded = Fixture.maxAbsoluteDifference(masked[0..., 7...], unmasked[0..., 7...])
        #expect(padded > 1e-3, Comment(rawValue: "the padded states moved by only \(padded)"))
    }

    private static func configuration() throws -> Flux2TextEncoderConfiguration {
        try JSONDecoder().decode(
            Flux2TextEncoderConfiguration.self, from: Data(configurationJSON.utf8))
    }

    /// An encoder with the fixture's weights in it.
    private static func loaded(_ fixture: [String: MLXArray]) throws -> Qwen3TextEncoder {
        let encoder = Qwen3TextEncoder(try configuration(), taps: taps)
        try encoder.update(
            parameters: ModuleParameters.unflattened(encoderWeights(fixture, layers: 6)),
            verify: .all)
        MLX.eval(encoder.parameters())
        return encoder
    }

    /// The fixture's weights, less what a tapped stack never builds: the final norm, and any
    /// layer past the deepest tap.
    ///
    /// The fixture is eight layers deep and tapped at six, so this drops the norm and two whole
    /// layers -- the same shape of saving as the published checkpoint's 36 tapped at 27.
    private static func encoderWeights(
        _ fixture: [String: MLXArray], layers: Int
    ) -> [String: MLXArray] {
        Fixture.weights(fixture, under: "").filter { key, _ in
            guard key.hasPrefix("model."), key != "model.norm.weight" else { return false }
            guard key.hasPrefix(layerPrefix) else { return true }
            let index = Int(key.dropFirst(layerPrefix.count).prefix(while: \.isNumber))
            return (index ?? .max) < layers
        }
    }

    private static let layerPrefix = "model.layers."
}
