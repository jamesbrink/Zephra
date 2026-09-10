import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the distilled schedule")
struct LTX2DistilledScheduleTests {
    @Test("nine sigmas from 1 to 0 make eight steps, and are what a plain schedule walks")
    func shape() {
        #expect(LTX2DistilledSchedule.firstStage.count == 9)
        #expect(LTX2DistilledSchedule.firstStage.first == 1)
        #expect(LTX2DistilledSchedule.firstStage.last == 0)
        #expect(LTX2DistilledSchedule.sigmas == LTX2DistilledSchedule.firstStage)
        let schedule = LTX2DistilledSchedule()
        #expect(schedule.sigmas == LTX2DistilledSchedule.firstStage)
        #expect(schedule.steps == 8)
    }

    @Test("the second stage is the first's last four rungs, three steps")
    func secondStage() {
        #expect(LTX2DistilledSchedule.secondStage == [0.909375, 0.725, 0.421875, 0.0])
        #expect(LTX2DistilledSchedule.secondStage == Array(LTX2DistilledSchedule.firstStage.suffix(4)))
        let schedule = LTX2DistilledSchedule(sigmas: LTX2DistilledSchedule.secondStage)
        #expect(schedule.steps == 3)
        #expect(schedule.eta == 1)
        #expect(schedule.noiseScale == 1)
    }

    @Test("entering a ladder noises the latent to its first sigma, flow-match style")
    func noised() {
        let schedule = LTX2DistilledSchedule(sigmas: LTX2DistilledSchedule.secondStage)
        let latent = MLXArray([2.0, -1.0, 0.5] as [Float])
        let noise = MLXArray([0.25, 1.0, -3.0] as [Float])
        let result = schedule.noised(latent, noise: noise).asArray(Float.self)
        let sigma: Float = 0.909375
        let expected = [
            0.25 * sigma + 2.0 * (1 - sigma), 1.0 * sigma - 1.0 * (1 - sigma), -3.0 * sigma + 0.5 * (1 - sigma),
        ] as [Float]
        for (value, want) in zip(result, expected) {
            #expect(abs(value - want) < 1e-6)
        }
        // On the first stage sigma is 1, so the latent contributes nothing and only the noise is left.
        let fresh = LTX2DistilledSchedule().noised(latent, noise: noise).asArray(Float.self)
        #expect(fresh == noise.asArray(Float.self))
    }

    @Test("a second-stage step reads its own ladder, not the first stage's")
    func secondStageStep() {
        let schedule = LTX2DistilledSchedule(sigmas: LTX2DistilledSchedule.secondStage)
        let x: Float = 0.8
        let v: Float = 0.3
        let n: Float = 0.1
        // Index 0 of the second ladder is 0.909375 to 0.725: index 5 of the first.
        let result = schedule.step(
            sample: MLXArray([x]), velocity: MLXArray([v]), index: 0, noise: MLXArray([n])
        ).asArray(Float.self)[0]
        let same = LTX2DistilledSchedule().step(
            sample: MLXArray([x]), velocity: MLXArray([v]), index: 5, noise: MLXArray([n])
        ).asArray(Float.self)[0]
        #expect(result == same)
        // Its last step, index 2, reads out the estimate at 0.421875.
        let last = schedule.step(
            sample: MLXArray([x]), velocity: MLXArray([v]), index: 2, noise: MLXArray([100])
        ).asArray(Float.self)[0]
        #expect(abs(last - (x - v * 0.421875)) < 1e-6)
    }

    @Test("with eta 1 the downstep sigma is sigmaNext squared over sigma")
    func downstep() {
        let terms = LTX2DistilledSchedule.ancestralTerms(sigma: 0.725, sigmaNext: 0.421875, eta: 1)
        let sigmaDown = 0.421875 * 0.421875 / 0.725
        #expect(abs(terms.ratio - sigmaDown / 0.725) < 1e-12)
        #expect(abs(terms.alphaRatio - (1 - 0.421875) / (1 - sigmaDown)) < 1e-12)
        let variance = 0.421875 * 0.421875 - sigmaDown * sigmaDown * pow((1 - 0.421875) / (1 - sigmaDown), 2)
        #expect(abs(terms.renoise - variance.squareRoot()) < 1e-12)
    }

    @Test("the last step is the denoised estimate, noise ignored")
    func lastStep() {
        let schedule = LTX2DistilledSchedule()
        let sample = MLXArray([2.0, -1.0] as [Float])
        let velocity = MLXArray([0.5, 0.5] as [Float])
        let noise = MLXArray([100.0, 100.0] as [Float])
        let sigma = Float(schedule.sigmas[7])
        let result = schedule.step(sample: sample, velocity: velocity, index: 7, noise: noise)
        let expected = sample - velocity * sigma
        #expect(result.asArray(Float.self) == expected.asArray(Float.self))
    }

    @Test("an ordinary step follows the reference arithmetic element by element")
    func middleStep() {
        let schedule = LTX2DistilledSchedule()
        let x: Float = 0.8
        let v: Float = 0.3
        let n: Float = 0.1
        let result = schedule.step(
            sample: MLXArray([x]), velocity: MLXArray([v]), index: 5, noise: MLXArray([n])
        ).asArray(Float.self)[0]
        let sigma = schedule.sigmas[5]
        let next = schedule.sigmas[6]
        let terms = LTX2DistilledSchedule.ancestralTerms(sigma: sigma, sigmaNext: next, eta: 1)
        let denoised = Double(x) - Double(v) * sigma
        let expected = (Double(x) * terms.ratio + denoised * (1 - terms.ratio)) * terms.alphaRatio
            + Double(n) * terms.renoise
        #expect(abs(Double(result) - expected) < 1e-5)
    }
}
