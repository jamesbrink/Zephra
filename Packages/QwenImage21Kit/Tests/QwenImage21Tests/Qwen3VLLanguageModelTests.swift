import Foundation
import MLX
import Testing

@testable import QwenImage21

/// The decoder stack against the reference, weights and all, at doll's-house size.
///
/// What it pins is the set of mistakes that compile perfectly and produce a different model:
/// the per-head query and key norms and where in the reshape they land, the bias-free
/// projections, grouped-query attention four to one, the causal mask, and — the one this model
/// is unusual for — that the answer is the **last layer's output before the final norm**,
/// which is what the pipeline's forward hook makes `hidden_states[-1]` mean.
@Suite("The Qwen3-VL decoder stack reproduces the reference's pre-norm hidden state")
struct Qwen3VLLanguageModelTests {
    @Test("the last layer's output matches the reference's hooked hidden state")
    func matchesTheReferencePreNormState() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Qwen3VLDollHouse.languageModel(fixture, prefix: "model.")
        let tokens = try #require(fixture["in.ids"])
        let reference = try #require(fixture["out.hidden"])

        let hidden = try model.hiddenStates(
            model.embedded(tokens),
            positions: Qwen3VLRotary.textPositions(count: tokens.dim(1)))

        #expect(hidden.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(hidden, reference)
        #expect(difference < 1e-4, Comment(rawValue: "the hidden state differs by \(difference)"))
    }

    @Test("it is not the normalised state, which is what an unhooked transformers 5 returns")
    func itIsNotTheNormalisedState() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Qwen3VLDollHouse.languageModel(fixture, prefix: "model.")
        let tokens = try #require(fixture["in.ids"])
        let normalised = try #require(fixture["out.normed"])

        let hidden = try model.hiddenStates(
            model.embedded(tokens),
            positions: Qwen3VLRotary.textPositions(count: tokens.dim(1)))

        // The two are far apart: a norm that divided a third of the signal away is exactly the
        // failure the hook exists to prevent, and this is the assertion that says the port
        // answers the other one.
        let difference = Fixture.maxAbsoluteDifference(hidden, normalised)
        #expect(difference > 1e-2, Comment(rawValue: "normed and pre-norm differ by only \(difference)"))
    }

    @Test("the stack's tensors are the checkpoint's, less the norm and head it never runs")
    func theWeightNamesLineUp() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = Qwen3VLLanguageModel(try Qwen3VLDollHouse.configuration().text)

        let ours = Set(model.parameters().flattened().map(\.0))
        let expected = Set(Qwen3VLDollHouse.weights(fixture, prefix: "model.").keys)
        #expect(ours == expected, Comment(rawValue: "mismatch: \(ours.symmetricDifference(expected).sorted())"))

        // The one tensor the fixture carries and the tree does not. `lm_head` is not in the
        // doll's house at all, since the dump builds `Qwen3VLTextModel` rather than the
        // conditional-generation wrapper; the published checkpoint does carry it, and
        // `WeightKeyCoverageTests` is where that is claimed.
        #expect(fixture["model.norm.weight"] != nil)
        #expect(!ours.contains("norm.weight"))
    }

    @Test("attention is causal: a token past the end cannot change the ones before it")
    func attentionIsCausal() throws {
        let fixture = try Fixture.load("text_encoder")
        let model = try Qwen3VLDollHouse.languageModel(fixture, prefix: "model.")
        let tokens = try #require(fixture["in.ids"])
        let positions = Qwen3VLRotary.textPositions(count: tokens.dim(1))

        var moved = tokens.asArray(Int32.self)
        moved[moved.count - 1] = 63
        let original = try model.hiddenStates(model.embedded(tokens), positions: positions)
        let changed = try model.hiddenStates(
            model.embedded(MLXArray(moved).reshaped(tokens.shape)), positions: positions)

        let prefix = Fixture.maxAbsoluteDifference(
            original[0..., ..<(tokens.dim(1) - 1)], changed[0..., ..<(tokens.dim(1) - 1)])
        #expect(prefix < 1e-6, Comment(rawValue: "the prefix moved by \(prefix)"))
        let last = Fixture.maxAbsoluteDifference(original[0..., (tokens.dim(1) - 1)...], changed[0..., (tokens.dim(1) - 1)...])
        #expect(last > 1e-3, Comment(rawValue: "the last state moved by only \(last)"))
    }
}
