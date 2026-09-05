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
        let ladders = fixture.filter { $0.key.hasSuffix(".sigmas") }
        #expect(ladders.count == 7, "the fixture names seven step-and-size pairs")
        for (key, expected) in ladders {
            let parts = key.split(separator: ".")
            let steps = try #require(Int(parts[0].dropFirst("steps".count)))
            let tokens = try #require(Int(parts[1].dropFirst("tokens".count)))
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

    @Test("one Euler step moves the sample by (sigma_next - sigma) * v")
    func eulerStep() {
        // With the shift off the ladder is exact: 1, 0.75, 0.5, 0.25, 0. So step 0 moves by
        // -0.25 v and the last step, from 0.25 to 0, by -0.25 v as well.
        let unshifted = Flux2SchedulerConfiguration(
            numTrainTimesteps: 1000, useDynamicShifting: false, shiftTerminal: nil,
            timeShiftType: "exponential")
        let scheduler = FlowMatchEulerScheduler(
            configuration: unshifted, steps: 4, imageSequenceLength: 4096)
        #expect(scheduler.sigmas == [1, 0.75, 0.5, 0.25, 0])
        let sample = MLXArray([1.0, 2.0] as [Float])
        let velocity = MLXArray([10.0, -4.0] as [Float])
        let first = scheduler.step(modelOutput: velocity, index: 0, sample: sample)
        #expect(first.asArray(Float.self) == [-1.5, 3.0])
        let last = scheduler.step(modelOutput: velocity, index: 3, sample: sample)
        #expect(last.asArray(Float.self) == [-1.5, 3.0])
        // And on the real ladder the gap is whatever the shift made it.
        let shifted = FlowMatchEulerScheduler(
            configuration: Self.klein, steps: 4, imageSequenceLength: 4096)
        let gap = Float(shifted.sigmas[1] - shifted.sigmas[0])
        let next = shifted.step(modelOutput: velocity, index: 0, sample: sample)
        #expect(Fixture.maxAbsoluteDifference(next, sample + velocity * gap) < 1e-6)
    }
}
