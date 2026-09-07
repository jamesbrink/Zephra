import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("what holding a first frame does to the latent, step by step")
struct FirstFrameConditioningTests {
    /// Two latent frames of one by two cells: four tokens, of which the first two are the held
    /// frame's.
    static let layout = LTX2LatentLayout(frames: 2, height: 1, width: 2)

    static func tokens(_ value: Float) -> MLXArray {
        MLXArray.full([1, layout.tokens, LTX2LatentLayout.channels], values: MLXArray(value))
    }

    @Test("the mask covers the first latent frame's tokens at the strength asked for, and no more")
    func maskCoversTheFirstFrame() {
        let mask = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: 0.4)
        #expect(mask.shape == [1, 4, 1])
        #expect(mask[0, 0, 0].item(Float.self) == 0.4)
        #expect(mask[0, 1, 0].item(Float.self) == 0.4)
        #expect(mask[0, 2, 0].item(Float.self) == 0)
        #expect(mask[0, 3, 0].item(Float.self) == 0)
        #expect(Self.layout.firstFrameTokens == 2)
    }

    @Test("a run held at full strength starts from the picture, and from noise everywhere else")
    func fullStrengthStartsFromThePicture() {
        let mask = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: 1)
        let start = LTX2FirstFrameConditioning.initial(
            noise: Self.tokens(7), clean: Self.tokens(3), mask: mask)
        #expect(start[0, 0, 0].item(Float.self) == 3)
        #expect(start[0, 3, 0].item(Float.self) == 7)
    }

    @Test("a partial strength mixes the two, and a strength of zero keeps the noise")
    func partialStrengthMixes() {
        for (strength, expected) in [(Float(0.25), Float(6)), (Float(0), Float(7))] {
            let mask = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: strength)
            let start = LTX2FirstFrameConditioning.initial(
                noise: Self.tokens(7), clean: Self.tokens(3), mask: mask)
            #expect(start[0, 0, 0].item(Float.self) == expected, Comment(rawValue: "\(strength)"))
            #expect(start[0, 3, 0].item(Float.self) == 7)
        }
    }

    @Test("the velocity taken back out carries the sample exactly to the blended estimate")
    func theConversionRoundTrips() {
        let mask = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: 0.5)
        let sample = Self.tokens(2)
        let estimate = LTX2FirstFrameConditioning.blended(
            Self.tokens(5), clean: Self.tokens(1), mask: mask)
        let velocity = LTX2FirstFrameConditioning.velocity(
            sample: sample, denoised: estimate, sigma: 0.725)
        let again = LTX2DistilledSchedule.denoised(sample, velocity: velocity, sigma: 0.725)
        #expect(Fixture.maxAbsoluteDifference(again, estimate) < 1e-6)
        // The held tokens land half way between 5 and 1; the rest are untouched.
        #expect(estimate[0, 0, 0].item(Float.self) == 3)
        #expect(estimate[0, 3, 0].item(Float.self) == 5)
    }

    @Test("after the step the picture is put back only where it is held outright")
    func onlyFullStrengthSurvivesTheStep() {
        let full = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: 1)
        let imposed = LTX2FirstFrameConditioning.imposed(
            Self.tokens(9), clean: Self.tokens(4), mask: full)
        #expect(imposed[0, 0, 0].item(Float.self) == 4)
        #expect(imposed[0, 3, 0].item(Float.self) == 9)

        // A partly held frame is left where the ancestral step put it, as the reference leaves
        // it: only strength 1 is the case the official pipeline answers by never stepping it.
        let partial = LTX2FirstFrameConditioning.mask(layout: Self.layout, strength: 0.9)
        let untouched = LTX2FirstFrameConditioning.imposed(
            Self.tokens(9), clean: Self.tokens(4), mask: partial)
        #expect(untouched[0, 0, 0].item(Float.self) == 9)
    }
}
