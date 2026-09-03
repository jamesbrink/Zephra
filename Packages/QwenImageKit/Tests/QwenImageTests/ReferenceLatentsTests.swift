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
            #expect(
                QwenImageReferenceLatents.startIndex(strength: 1, steps: steps) == 0,
                "\(steps) steps")
        }
    }

    @Test("strength is a share of the steps, not a noise level")
    func startIndexIsAShareOfTheSteps() {
        // 4 * 0.6 = 2.4, so two of the four steps run and the loop enters at 2.
        #expect(QwenImageReferenceLatents.startIndex(strength: 0.6, steps: 4) == 2)
        // 4 * 0.9 = 3.6, which rounds to the whole run: entry 0, where the mix is pure noise.
        #expect(QwenImageReferenceLatents.startIndex(strength: 0.9, steps: 4) == 0)
        #expect(QwenImageReferenceLatents.startIndex(strength: 0.5, steps: 4) == 2)
    }

    @Test("a strength too small to buy a whole step still buys one, never none")
    func tinyStrengthRunsTheLastStep() {
        // 4 * 0.1 is 0.4, which rounds to nothing; running no steps would hand the picture back.
        #expect(QwenImageReferenceLatents.startIndex(strength: 0.1, steps: 4) == 3)
        #expect(QwenImageReferenceLatents.startIndex(strength: 0, steps: 4) == 3)
    }

    @Test("the four-step ladder's tail no longer swallows most of the strength range")
    func strengthsSpreadAcrossTheLadder() {
        // The regression this mapping exists for. The four-step ladder ends at the configured
        // terminal sigma, near zero, so choosing the first sigma at or below the strength sent
        // every strength from 0.1 to 0.4 to that last rung — one step from almost no noise, and
        // the picture handed straight back.
        let ladder = sigmas(steps: 4)
        #expect(ladder[3] < 0.05, "the tail really is that low")

        let entries = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9].map {
            QwenImageReferenceLatents.startIndex(strength: $0, steps: 4)
        }
        #expect(Set(entries) == [0, 1, 2, 3], "every rung is reachable")
        #expect(entries.filter { $0 == 3 }.count == 3, "only 0.1 to 0.3 run a single step")
        // Four steps is four entry points, so the bottom of the range has nowhere else to go:
        // one step is the fewest that can run, and it necessarily starts at the last sigma.
        // That is the distillation's granularity, not this mapping's doing — the nine-step
        // Z-Image ladder spreads the same range over nine.
        #expect(QwenImageReferenceLatents.startIndex(strength: 0.4, steps: 4) == 2)
        #expect(ladder[2] > 0.4, "0.4 now enters at a real noise level, where it used to not")
    }

    @Test("the entry point falls as the strength rises, and never leaves the run")
    func startIndexIsMonotonic() {
        let indices = stride(from: 0.0, through: 1.0, by: 0.05).map {
            QwenImageReferenceLatents.startIndex(strength: $0, steps: 8)
        }
        #expect(indices.allSatisfy { (0..<8).contains($0) })
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $0 >= $1 }, "never goes back down")
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
