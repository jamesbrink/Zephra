import Foundation
import MLX
import MLXNN
import Testing

@testable import QwenImage

/// The conditioning encoder against the reference, weights and all.
///
/// The fixture is a two-layer, 64-wide stand-in, which is the right size: every way this port
/// could be wrong is structural, and structure shows up at any width. What it checks is the set
/// of things that compile perfectly while producing a different model -- the bias on the query,
/// key, and value projections, how grouped-query heads are expanded, the SwiGLU gate order, and
/// which hidden state comes out.
@Suite("Text encoder parity")
struct TextEncoderParityTests {
    private static let configuration = QwenImageTextEncoderConfiguration(
        hiddenSize: 64,
        numHiddenLayers: 2,
        numAttentionHeads: 4,
        numKeyValueHeads: 2,
        intermediateSize: 128,
        rmsNormEps: 1e-6,
        ropeTheta: 1_000_000,
        vocabSize: 100
    )

    @Test("hidden states match the reference stack")
    func matchesReference() throws {
        let fixture = try Fixture.load("text_encoder")
        let tokens = try #require(fixture["input_ids"])
        let reference = try #require(fixture["last_hidden_state"])

        let encoder = Qwen25TextEncoder(Self.configuration)
        let weights = fixture.filter { $0.key.hasPrefix("model.") }
        try encoder.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
        MLX.eval(encoder.parameters())

        let hidden = encoder(tokens, dropping: 0)
        #expect(hidden.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(hidden, reference)
        #expect(difference < 2e-4, "hidden states differ by \(difference)")
    }

    @Test("the template prefix is dropped from the front")
    func dropsThePrefix() throws {
        let fixture = try Fixture.load("text_encoder")
        let tokens = try #require(fixture["input_ids"])
        let reference = try #require(fixture["last_hidden_state"])

        let encoder = Qwen25TextEncoder(Self.configuration)
        let weights = fixture.filter { $0.key.hasPrefix("model.") }
        try encoder.update(parameters: ModuleParameters.unflattened(weights), verify: .all)

        let dropped = encoder(tokens, dropping: 2)
        #expect(dropped.shape == [1, reference.shape[1] - 2, 64])
        #expect(Fixture.maxAbsoluteDifference(dropped, reference[0..., 2...]) < 2e-4)
    }

    @Test("every tensor the reference stack carries is one this module has")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("text_encoder")
        let encoder = Qwen25TextEncoder(Self.configuration)
        let ours = Set(encoder.parameters().flattened().map(\.0))
        let reference = Set(fixture.keys.filter { $0.hasPrefix("model.") })
        #expect(reference.subtracting(ours).isEmpty, "unloaded: \(reference.subtracting(ours).sorted())")
        #expect(ours.subtracting(reference).isEmpty, "unfilled: \(ours.subtracting(reference).sorted())")
    }
}
