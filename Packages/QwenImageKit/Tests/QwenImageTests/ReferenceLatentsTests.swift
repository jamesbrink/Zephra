import Foundation
import MLX
import Testing

@testable import QwenImage

/// Where a strength lands on the four-step ladder the shipped model actually runs, and what the
/// mix at that rung is. Both are pure functions; nothing here loads a weight.
@Suite("Reference latents")
struct ReferenceLatentsTests {
    /// Qwen-Image-2512's published `scheduler/scheduler_config.json`, as `SchedulerTests` reads
    /// it, so this pins the ladder the four-step adapter was distilled against.
    private static let configuration = QwenImageSchedulerConfiguration(
        numTrainTimesteps: 1000,
        shift: 1,
        useDynamicShifting: true,
        baseShift: 0.5,
        maxShift: 0.9,
        baseImageSeqLen: 256,
        maxImageSeqLen: 8192,
        shiftTerminal: 0.02,
        timeShiftType: "exponential"
    )

    private func sigmas(steps: Int) -> [Double] {
        FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: steps, imageSequenceLength: 4096
        ).sigmas
    }

    @Test("a strength of 1 runs every step, so a reference at full strength changes nothing")
    func fullStrengthStartsAtZero() {
        for steps in [1, 4, 8, 12] {
            let index = QwenImageReferenceLatents.startIndex(
                sigmas: sigmas(steps: steps), strength: 1, steps: steps)
            #expect(index == 0, "\(steps) steps")
        }
    }

    @Test("a strength below the whole ladder still runs the last step, never none")
    func zeroStrengthRunsTheLastStep() {
        for steps in [1, 4, 8, 12] {
            let index = QwenImageReferenceLatents.startIndex(
                sigmas: sigmas(steps: steps), strength: 0, steps: steps)
            #expect(index == steps - 1, "\(steps) steps")
        }
    }

    @Test("the chosen step is the first at or below the strength, and the one before is above")
    func startIndexStraddlesTheStrength() {
        let ladder = sigmas(steps: 8)
        for strength in [0.2, 0.4, 0.6, 0.8] {
            let index = QwenImageReferenceLatents.startIndex(
                sigmas: ladder, strength: strength, steps: 8)
            #expect(ladder[index] <= strength, "strength \(strength)")
            if index > 0 { #expect(ladder[index - 1] > strength, "strength \(strength)") }
        }
    }

    @Test("the entry point falls as the strength falls, and never leaves the run")
    func startIndexIsMonotonic() {
        let ladder = sigmas(steps: 8)
        let indices = stride(from: 1.0, through: 0.0, by: -0.05).map {
            QwenImageReferenceLatents.startIndex(sigmas: ladder, strength: $0, steps: 8)
        }
        #expect(indices.allSatisfy { (0..<8).contains($0) })
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $0 <= $1 }, "never goes back up")
    }

    @Test("the mix is the schedule's own interpolation, and its ends are the two inputs")
    func mixInterpolates() {
        let reference = MLXArray([1, 2, 3, 4] as [Float], [1, 4])
        let noise = MLXArray([-1, -1, -1, -1] as [Float], [1, 4])

        let atOne = QwenImageReferenceLatents.mixed(
            reference: reference, noise: noise, sigma: 1)
        #expect(Fixture.maxAbsoluteDifference(atOne, noise) < 1e-6, "all noise")

        let atZero = QwenImageReferenceLatents.mixed(
            reference: reference, noise: noise, sigma: 0)
        #expect(Fixture.maxAbsoluteDifference(atZero, reference) < 1e-6, "all picture")

        let half = QwenImageReferenceLatents.mixed(
            reference: reference, noise: noise, sigma: 0.5)
        let expected = MLXArray([0, 0.5, 1, 1.5] as [Float], [1, 4])
        #expect(Fixture.maxAbsoluteDifference(half, expected) < 1e-6)
    }
}
