import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

@Suite("The transformer reproduces the reference, block by block and whole")
struct TransformerParityTests {
    @Test("one block's prefill matches the reference over an edit layout")
    func blockPrefill() throws {
        let fixture = try Fixture.load("transformer_block")
        let configuration = try TransformerFixture.configuration()
        let block = QwenImage21TransformerBlock(
            dim: configuration.innerDim,
            heads: configuration.numAttentionHeads,
            headDim: configuration.attentionHeadDim,
            mlpHidden: configuration.mlpHiddenSize,
            eps: configuration.eps)
        try PackedWeightLoading.load(
            into: block,
            weights: QwenImage21TransformerWeights.sanitized(
                Fixture.weights(fixture, under: "block.")),
            manifest: nil)

        let mask = MLXArray(try Fixture.flags(fixture, "in.targetTokenMask"))
        let hidden = try block(
            try #require(fixture["in.hidden"]),
            modulation: QwenImage21SharedModulation.split(
                try #require(fixture["in.modulationFirst"]), targetTokenMask: mask),
            frequencies: try Self.rotary(fixture),
            plan: QwenImage21AttentionPlan.prefill(
                segments: try Self.segments(fixture),
                keyValid: nil,
                sequenceLength: mask.dim(0)),
            cache: nil,
            mode: nil,
            prefixLength: try Self.prefixLength(fixture))

        let expected = try #require(fixture["out.prefill"])
        #expect(hidden.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(hidden, expected) < 1e-4)
    }

    @Test(arguments: ["textOnly", "oneReference"])
    func wholeModelPredictsTheReferenceVelocity(_ label: String) throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerFixture.model(fixture)
        let layout = try TransformerFixture.layout(label, in: fixture, shapes: label)

        let velocity = try model(
            latents: try #require(fixture["\(label).in.hidden"]),
            text: try #require(fixture["\(label).in.encoder"]),
            timestep: try #require(fixture["\(label).in.timestep"]),
            layout: layout,
            frequencies: try TransformerFixture.frequencies(layout))

        let expected = try #require(fixture["\(label).out.velocity"])
        #expect(velocity.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(velocity, expected) < 1e-4)
    }

    /// The only thing that exercises the joint key-valid mask, and it is not a mask that can be
    /// sliced off the front: the text positions of the joint sequence are interleaved with the
    /// condition image's, so a port that treated the prompt's padding as a prefix would drop the
    /// wrong two tokens and still make a picture.
    @Test("a right-padded prompt drops the padded keys and nothing else")
    func paddedPrompt() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try TransformerFixture.model(fixture)
        let layout = try TransformerFixture.layout(
            "padded", in: fixture, shapes: "oneReference")

        let velocity = try model(
            latents: try #require(fixture["padded.in.hidden"]),
            text: try #require(fixture["padded.in.encoder"]),
            timestep: try #require(fixture["padded.in.timestep"]),
            layout: layout,
            frequencies: try TransformerFixture.frequencies(layout),
            promptMask: try Fixture.flags(fixture, "padded.in.promptMask"))

        let expected = try #require(fixture["padded.out.velocity"])
        #expect(velocity.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(velocity, expected) < 1e-4)
    }

    @Test("every checkpoint tensor lands somewhere, and every parameter is filled")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = QwenImage21Transformer(try TransformerFixture.configuration())
        let wanted = Set(model.parameters().flattened().map(\.0))
        let checkpoint = Set(Fixture.weights(fixture, under: "model.").keys)
        let supplied = Set(checkpoint.map(QwenImage21TransformerWeights.moduleName(of:)))

        let missing = wanted.subtracting(supplied).sorted()
        let extra = supplied.subtracting(wanted).sorted()
        #expect(missing.isEmpty, Comment(rawValue: "no weight for \(missing)"))
        #expect(extra.isEmpty, Comment(rawValue: "no home for \(extra)"))

        // The rename is a round trip, or the packed manifest and the weight stream would ask the
        // shards for names they do not carry.
        let back = Set(supplied.map(QwenImage21TransformerWeights.checkpointName(of:)))
        #expect(back == checkpoint)
        #expect(checkpoint.contains("modulation.1.weight"))
        #expect(checkpoint.contains("transformer_blocks.0.attn.to_out.0.weight"))
    }

    static func rotary(_ fixture: [String: MLXArray]) throws -> RotaryFrequencies {
        RotaryFrequencies(
            cos: try #require(fixture["in.cos"]), sin: try #require(fixture["in.sin"]))
    }

    static func segments(_ fixture: [String: MLXArray]) throws
        -> [QwenImage21AttentionSegments.Segment]
    {
        let flat = try Fixture.ints(fixture, "in.segments")
        return stride(from: 0, to: flat.count, by: 3).map {
            QwenImage21AttentionSegments.Segment(
                start: flat[$0], end: flat[$0 + 1], isText: flat[$0 + 2] != 0)
        }
    }

    static func prefixLength(_ fixture: [String: MLXArray]) throws -> Int {
        try Fixture.ints(fixture, "in.prefixLength")[0]
    }
}
