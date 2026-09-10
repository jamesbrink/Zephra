import Foundation
import MLX
import Testing

@testable import Wan

@Suite("the distilled schedule walks diffusers' shift-8 grid")
struct WanDistilledScheduleTests {
    @Test("the grid is the reference scheduler's, a thousand sigmas and timesteps")
    func grid() throws {
        let fixture = try Fixture.load("schedule")
        #expect(WanDistilledSchedule.sigmas.count == 1000)
        #expect(WanDistilledSchedule.sigmas.first == 1)
        let sigmas = MLXArray(WanDistilledSchedule.sigmas.map(Float.init))
        let timesteps = MLXArray(WanDistilledSchedule.gridTimesteps.map(Float.init))
        #expect(Fixture.maxAbsoluteDifference(sigmas, try #require(fixture["sigmas"])) < 1e-6)
        #expect(Fixture.maxAbsoluteDifference(timesteps, try #require(fixture["timesteps"])) < 1e-3)
    }

    @Test("three steps at 1000, 757 and 522 take the nearest grid sigma")
    func stepSigmas() throws {
        let fixture = try Fixture.load("schedule")
        let schedule = WanDistilledSchedule()
        #expect(schedule.steps == 3)
        #expect(try #require(fixture["step_timesteps"]).asArray(Float.self) == [1000, 757, 522])
        let expected = try #require(fixture["step_sigmas"]).asArray(Float.self)
        for (index, sigma) in expected.enumerated() {
            #expect(abs(Float(schedule.sigma(at: index)) - sigma) < 1e-6, Comment(rawValue: "step \(index)"))
        }
        // 757 is not on the grid; 756.7567 is the nearest, at index 720.
        #expect(abs(WanDistilledSchedule.gridTimesteps[720] - 756.7567567) < 1e-6)
        #expect(WanDistilledSchedule.sigma(forTimestep: 757) == WanDistilledSchedule.sigmas[720])
    }

    @Test("each step denoises at its sigma and re-noises at the next, the last one reading out")
    func steps() throws {
        let fixture = try Fixture.load("schedule")
        let schedule = WanDistilledSchedule()
        var sample = try #require(fixture["in.x"])
        for index in 0..<schedule.steps {
            let velocity = try #require(fixture["in.velocity.\(index)"])
            let denoised = WanDistilledSchedule.denoised(sample, velocity: velocity, sigma: schedule.sigma(at: index))
            #expect(
                Fixture.maxAbsoluteDifference(denoised, try #require(fixture["out.denoised.\(index)"])) < 1e-5,
                Comment(rawValue: "denoised \(index)"))
            let noise = fixture["in.noise.\(index)"] ?? MLX.full(sample.shape, values: MLXArray(Float(100)))
            sample = schedule.step(sample: sample, velocity: velocity, index: index, noise: noise)
            if let next = fixture["out.next.\(index)"] {
                #expect(Fixture.maxAbsoluteDifference(sample, next) < 1e-5, Comment(rawValue: "next \(index)"))
            } else {
                // The last step ignores the noise: the answer is the estimate itself.
                #expect(Fixture.maxAbsoluteDifference(sample, denoised) == 0)
            }
        }
    }
}
