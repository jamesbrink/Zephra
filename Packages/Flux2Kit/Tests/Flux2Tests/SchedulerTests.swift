import Foundation
import MLX
import Testing

@testable import Flux2

@Suite("The schedule is the reference pipeline's, shift and all")
struct SchedulerTests {
    private static let klein = Flux2SchedulerConfiguration(
        numTrainTimesteps: 1000, useDynamicShifting: true, shiftTerminal: nil,
        timeShiftType: "exponential")

    @Test("the sigma ladder matches the reference at every step count and size dumped")
    func sigmasMatchReference() throws {
        let fixture = try Fixture.load("scheduler")
        for (key, expected) in fixture where key.hasSuffix(".sigmas") {
            let parts = key.split(separator: ".")
            let steps = Int(parts[0].dropFirst("steps".count))!
            let tokens = Int(parts[1].dropFirst("tokens".count))!
            let scheduler = FlowMatchEulerScheduler(
                configuration: Self.klein, steps: steps, imageSequenceLength: tokens)
            let ours = MLXArray(scheduler.sigmas.map(Float.init))
            #expect(ours.shape == expected.shape, Comment(rawValue: key))
            #expect(Fixture.maxAbsoluteDifference(ours, expected) < 1e-6, Comment(rawValue: key))
            let mu = try #require(fixture["steps\(steps).tokens\(tokens).mu"]).item(Float.self)
            #expect(
                abs(Float(EmpiricalShift.mu(imageSequenceLength: tokens, steps: steps)) - mu)
                    < 1e-6, Comment(rawValue: key))
        }
    }

    @Test("a 1024-pixel image in four steps walks the ladder the reference walks")
    func kleinDefaultLadder() {
        let scheduler = FlowMatchEulerScheduler(
            configuration: Self.klein, steps: 4, imageSequenceLength: 4096)
        let expected = [1.0, 0.9674, 0.9081, 0.7672, 0]
        for (ours, theirs) in zip(scheduler.sigmas, expected) {
            #expect(abs(ours - theirs) < 1e-4)
        }
        #expect(abs(EmpiricalShift.mu(imageSequenceLength: 4096, steps: 4) - 2.29118) < 1e-5)
    }

    @Test("sigmas fall strictly, end at zero, and number one more than the steps")
    func ladderShape() {
        for (steps, tokens) in [(1, 4096), (4, 1024), (8, 4096), (28, 9216)] {
            let scheduler = FlowMatchEulerScheduler(
                configuration: Self.klein, steps: steps, imageSequenceLength: tokens)
            #expect(scheduler.sigmas.count == steps + 1)
            #expect(scheduler.sigmas.last == 0)
            #expect(scheduler.sigmas.first == 1)
            #expect(zip(scheduler.sigmas, scheduler.sigmas.dropFirst()).allSatisfy { $0 > $1 })
            #expect(scheduler.timesteps.count == steps)
        }
    }

    @Test("the Euler step moves by the gap to the next sigma")
    func eulerStep() {
        let scheduler = FlowMatchEulerScheduler(
            configuration: Self.klein, steps: 4, imageSequenceLength: 4096)
        let sample = MLXArray([1.0, 2.0] as [Float])
        let velocity = MLXArray([10.0, 10.0] as [Float])
        let next = scheduler.step(modelOutput: velocity, index: 0, sample: sample)
        let gap = Float(scheduler.sigmas[1] - scheduler.sigmas[0])
        #expect(Fixture.maxAbsoluteDifference(next, sample + velocity * gap) < 1e-6)
    }
}
