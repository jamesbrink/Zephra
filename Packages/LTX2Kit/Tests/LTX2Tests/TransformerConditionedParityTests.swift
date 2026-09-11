import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import LTX2

@Suite("the transformer holds a first frame the way the reference conditions on one")
struct TransformerConditionedParityTests {
    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2Transformer {
        let model = LTX2Transformer(TransformerParityTests.configuration)
        try PackedWeightLoading.load(
            into: model,
            weights: LTX2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        return model
    }

    @Test(
        "a held frame reproduces the reference's per-token timestep, at full and partial strength",
        arguments: [("1", Float(1)), ("0_6", Float(0.6))])
    func conditionedForward(label: String, strength: Float) throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let model = try Self.loaded(fixture)
        let output = try model(
            tokens: try #require(fixture["in.tokens"]),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: TransformerParityTests.layout,
            frameRate: 24,
            firstFrameStrength: strength)
        let expected = try #require(fixture["out.tokens.\(label)"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
    }

    @Test(
        "a run of held frames reproduces the reference, the keyframe embedding on the first alone",
        arguments: [("1", Float(1)), ("0_6", Float(0.6))])
    func heldSpanForward(label: String, strength: Float) throws {
        let fixture = try Fixture.load("transformer_conditioned_span")
        let model = try Self.loaded(fixture)
        let heldFrames = try #require(fixture["in.held_frames"]).item(Int32.self)
        #expect(heldFrames == 2)
        let output = try model(
            tokens: try #require(fixture["in.tokens"]),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: TransformerParityTests.layout,
            frameRate: 24,
            firstFrameStrength: strength,
            heldFrames: Int(heldFrames))
        let expected = try #require(fixture["out.tokens.\(label)"])
        #expect(output.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(output, expected) < 1e-4)
        // Holding two frames is not holding one: the second frame's tokens are told a different
        // noise level, and the answer moves with them.
        let oneFrame = try #require(try Fixture.load("transformer_conditioned")["out.tokens.\(label)"])
        #expect(Fixture.maxAbsoluteDifference(output, oneFrame) > 1e-3)
    }

    @Test("holding nothing is not the same answer as holding the frame")
    func conditioningChangesTheAnswer() throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let model = try Self.loaded(fixture)
        let plain = try model(
            tokens: try #require(fixture["in.tokens"]),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: TransformerParityTests.layout,
            frameRate: 24)
        for label in ["1", "0_6"] {
            let held = try #require(fixture["out.tokens.\(label)"])
            #expect(Fixture.maxAbsoluteDifference(plain, held) > 1e-2, Comment(rawValue: label))
        }
    }

    @Test("no held frame is bit for bit the path that was there before")
    func theTextToVideoPathIsUntouched() throws {
        let fixture = try Fixture.load("transformer_model")
        let model = try Self.loaded(fixture)
        let output = try model(
            tokens: try #require(fixture["in.tokens"]),
            text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"]),
            layout: TransformerParityTests.layout,
            frameRate: 24,
            firstFrameStrength: nil)
        #expect(Fixture.maxAbsoluteDifference(output, try #require(fixture["out.tokens"])) < 1e-4)
    }

    @Test("a strength of zero holds nothing, and answers what an unconditioned run answers")
    func zeroStrengthHoldsNothing() throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let model = try Self.loaded(fixture)
        let arguments = (
            tokens: try #require(fixture["in.tokens"]), text: try #require(fixture["in.text"]),
            sigma: try #require(fixture["in.sigma"])
        )
        let plain = try model(
            tokens: arguments.tokens, text: arguments.text, sigma: arguments.sigma,
            layout: TransformerParityTests.layout, frameRate: 24)
        let held = try model(
            tokens: arguments.tokens, text: arguments.text, sigma: arguments.sigma,
            layout: TransformerParityTests.layout, frameRate: 24, firstFrameStrength: 0)
        // Not bit for bit: the rows are selected from two batch elements rather than one. The
        // two sigmas are equal, so the answer is.
        #expect(Fixture.maxAbsoluteDifference(plain, held) < 1e-5)
    }

    @Test("the blend that surrounds a step is the reference's, in x0 space at the scalar sigma")
    func stepArithmetic() throws {
        let fixture = try Fixture.load("transformer_conditioned")
        let sample = try #require(fixture["in.tokens"])
        let velocity = try #require(fixture["in.velocity"])
        let clean = try #require(fixture["in.clean"])
        let mask = try #require(fixture["in.mask"])
        let sigma = try #require(fixture["in.sigma"]).item(Float.self)

        let x0 = LTX2DistilledSchedule.denoised(sample, velocity: velocity, sigma: Double(sigma))
        #expect(Fixture.maxAbsoluteDifference(x0, try #require(fixture["out.x0"])) < 1e-4)

        let conditioned = LTX2FirstFrameConditioning.blended(x0, clean: clean, mask: mask)
        #expect(
            Fixture.maxAbsoluteDifference(conditioned, try #require(fixture["out.x0_conditioned"]))
                < 1e-4)

        let back = LTX2FirstFrameConditioning.velocity(
            sample: sample, denoised: conditioned, sigma: sigma)
        #expect(Fixture.maxAbsoluteDifference(back, try #require(fixture["out.velocity"])) < 1e-4)
    }
}
