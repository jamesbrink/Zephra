import Foundation
import MLX
import Testing

@testable import QwenImage21

@Suite("The schedule is the reference pipeline's, shift, stretch and all")
struct ScheduleTests {
    private static let published = QwenImage21SchedulerConfiguration()

    @Test("the sigma ladder matches the reference at every step count and size dumped")
    func sigmasMatchReference() throws {
        let fixture = try Fixture.load("scheduler")
        let ladders = fixture.filter { $0.key.hasSuffix(".sigmas") }
        #expect(ladders.count == 7, "the fixture names seven step-and-size pairs")
        for (key, expected) in ladders {
            let (steps, tokens) = try Self.pair(in: key)
            let schedule = QwenImage21Schedule(
                configuration: Self.published, steps: steps, imageSequenceLength: tokens)
            let ours = MLXArray(schedule.sigmas.map(Float.init))
            #expect(ours.shape == expected.shape, Comment(rawValue: key))
            #expect(Fixture.maxAbsoluteDifference(ours, expected) < 1e-6, Comment(rawValue: key))
        }
    }

    @Test("the timestep handed to the transformer is the sigma times a thousand")
    func timestepsMatchReference() throws {
        let fixture = try Fixture.load("scheduler")
        for (key, expected) in fixture.filter({ $0.key.hasSuffix(".timesteps") }) {
            let (steps, tokens) = try Self.pair(in: key)
            let schedule = QwenImage21Schedule(
                configuration: Self.published, steps: steps, imageSequenceLength: tokens)
            let ours = MLXArray(schedule.timesteps.map(Float.init))
            #expect(ours.shape == expected.shape, Comment(rawValue: key))
            // A thousandth of a timestep, which is a millionth of a sigma.
            #expect(Fixture.maxAbsoluteDifference(ours, expected) < 1e-3, Comment(rawValue: key))
        }
    }

    @Test("the shift is the published line, extrapolated past max_image_seq_len rather than clamped")
    func shiftMatchesReference() throws {
        let fixture = try Fixture.load("scheduler")
        for (key, expected) in fixture.filter({ $0.key.hasSuffix(".mu") }) {
            let (_, tokens) = try Self.pair(in: key)
            let ours = QwenImage21DynamicShift.mu(
                imageSequenceLength: tokens, configuration: Self.published)
            #expect(abs(Float(ours) - expected.item(Float.self)) < 1e-6, Comment(rawValue: key))
        }
        // 16384 tokens is twice the ceiling, and the answer is past maxShift because nothing
        // clamps: 1.3129, not 0.9.
        let beyond = QwenImage21DynamicShift.mu(
            imageSequenceLength: 16384, configuration: Self.published)
        #expect(beyond > Self.published.maxShift)
    }

    @Test("a 1024-pixel image in forty steps walks the ladder the model card describes")
    func defaultLadder() {
        let schedule = QwenImage21Schedule(
            configuration: Self.published, steps: 40, imageSequenceLength: 4096)
        #expect(abs(schedule.sigmas[0] - 1.0) < 1e-6)
        #expect(abs(schedule.sigmas[1] - 0.986964) < 1e-5)
        #expect(abs(schedule.sigmas[39] - 0.02) < 1e-5, "shift_terminal, not zero")
        #expect(schedule.sigmas[40] == 0, "the appended rung")
        #expect(abs(schedule.timesteps[0] - 1000) < 1e-3)
    }

    @Test("sigmas fall strictly, end at zero, and number one more than the steps")
    func ladderShape() {
        for (steps, tokens) in [(2, 4096), (4, 1024), (40, 4096), (50, 16384)] {
            let schedule = QwenImage21Schedule(
                configuration: Self.published, steps: steps, imageSequenceLength: tokens)
            #expect(schedule.sigmas.count == steps + 1)
            #expect(schedule.sigmas.last == 0)
            #expect(schedule.sigmas.first == 1)
            #expect(zip(schedule.sigmas, schedule.sigmas.dropFirst()).allSatisfy { $0 > $1 })
            #expect(schedule.timesteps.count == steps)
        }
    }

    @Test("a one-step ladder is finite, where the reference's terminal stretch is not")
    func singleStepIsFinite() {
        // The stretch divides by `1 - sigmas.last` over `1 - shift_terminal`, and a one-step
        // ladder's last sigma is 1, so the reference divides by zero and returns NaN. The port
        // leaves the ladder alone instead; a NaN sigma is a run that produces nothing at all.
        let schedule = QwenImage21Schedule(
            configuration: Self.published, steps: 1, imageSequenceLength: 4096)
        #expect(schedule.sigmas == [1, 0])
        #expect(schedule.sigmas.allSatisfy { $0.isFinite })
    }

    @Test("one Euler step moves the sample by (sigma_next - sigma) times the velocity")
    func eulerStep() {
        // With every bend switched off the ladder is exact: 1, 0.75, 0.5, 0.25, 0.
        let plain = QwenImage21SchedulerConfiguration(
            shiftTerminal: nil, useDynamicShifting: false)
        let schedule = QwenImage21Schedule(
            configuration: plain, steps: 4, imageSequenceLength: 4096)
        #expect(schedule.sigmas == [1, 0.75, 0.5, 0.25, 0])
        let sample = MLXArray([1.0, 2.0] as [Float])
        let velocity = MLXArray([10.0, -4.0] as [Float])
        let moved = schedule.step(modelOutput: velocity, index: 0, sample: sample)
        #expect(moved.asArray(Float.self) == [-1.5, 3.0])
    }

    /// `steps40.tokens4096.sigmas` read back as (40, 4096).
    private static func pair(in key: String) throws -> (steps: Int, tokens: Int) {
        let parts = key.split(separator: ".")
        let steps = try #require(Int(parts[0].dropFirst("steps".count)), Comment(rawValue: key))
        let tokens = try #require(Int(parts[1].dropFirst("tokens".count)), Comment(rawValue: key))
        return (steps, tokens)
    }
}
