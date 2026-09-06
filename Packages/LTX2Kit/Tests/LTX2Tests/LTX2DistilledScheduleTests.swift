import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the distilled schedule")
struct LTX2DistilledScheduleTests {
    @Test("nine sigmas from 1 to 0 make eight steps")
    func shape() {
        #expect(LTX2DistilledSchedule.sigmas.count == 9)
        #expect(LTX2DistilledSchedule.sigmas.first == 1)
        #expect(LTX2DistilledSchedule.sigmas.last == 0)
        #expect(LTX2DistilledSchedule().steps == 8)
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
        let sigma = Float(LTX2DistilledSchedule.sigmas[7])
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
        let sigma = LTX2DistilledSchedule.sigmas[5]
        let next = LTX2DistilledSchedule.sigmas[6]
        let terms = LTX2DistilledSchedule.ancestralTerms(sigma: sigma, sigmaNext: next, eta: 1)
        let denoised = Double(x) - Double(v) * sigma
        let expected = (Double(x) * terms.ratio + denoised * (1 - terms.ratio)) * terms.alphaRatio
            + Double(n) * terms.renoise
        #expect(abs(Double(result) - expected) < 1e-5)
    }
}
