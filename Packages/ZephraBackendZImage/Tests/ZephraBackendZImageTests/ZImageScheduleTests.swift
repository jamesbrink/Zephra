import Foundation
import MLX
import Testing
import ZImage

/// The sigma ladder the SDEdit patch reads, and where a strength lands on it.
///
/// Nothing here loads weights. The ladder is a pure function of the scheduler config, and the
/// entry point is a pure function of the ladder, which is the whole reason `ReferenceLatents`
/// keeps them separate from the pipeline.
@Suite("Z-Image's denoising schedule")
struct ZImageScheduleTests {
    /// The real `scheduler/scheduler_config.json` from `mzbac/Z-Image-Turbo-8bit`, decoded the
    /// way the pipeline decodes it, so this pins the shipped schedule and not an invented one.
    /// Decoded rather than held: `ZImageSchedulerConfig` is a vendored `Decodable` with no
    /// public initializer and no `Sendable` conformance, so this is both the only way to build
    /// one and the reason it is not a stored static.
    private var config: ZImageSchedulerConfig {
        get throws {
            let json = """
                {
                  "_class_name": "FlowMatchEulerDiscreteScheduler",
                  "num_train_timesteps": 1000,
                  "use_dynamic_shifting": false,
                  "shift": 3.0
                }
                """
            return try JSONDecoder().decode(ZImageSchedulerConfig.self, from: Data(json.utf8))
        }
    }

    private func sigmas(steps: Int) throws -> [Float] {
        try FlowMatchEulerScheduler(numInferenceSteps: steps, config: config)
            .sigmas.asArray(Float.self)
    }

    @Test("the ladder starts at 1, falls all the way, and carries a trailing zero", arguments: [
        1, 2, 4, 9, 20,
    ])
    func ladderShape(steps: Int) throws {
        let ladder = try sigmas(steps: steps)
        #expect(ladder.count == steps + 1, "one sigma per step, plus the zero `step` reads")
        #expect(ladder[0] == 1.0, "the first step is pure noise, whatever the step count")
        #expect(ladder.last == 0.0)
        #expect(zip(ladder, ladder.dropFirst()).allSatisfy { $0 > $1 }, "strictly decreasing")
    }

    @Test("the nine-step ladder is the one the shipped shift of 3 produces")
    func nineStepLadder() throws {
        let ladder = try sigmas(steps: 9)
        let expected: [Float] = [
            1.0, 0.954694, 0.900359, 0.833998, 0.751121, 0.644686, 0.502985, 0.305009, 0.008929,
            0,
        ]
        #expect(ladder.count == expected.count)
        for (got, want) in zip(ladder, expected) {
            #expect(abs(got - want) < 1e-4, "sigma \(got) should be \(want)")
        }
    }

    @Test("a strength of 1 runs every step, so a reference at full strength changes nothing")
    func fullStrengthStartsAtZero() throws {
        for steps in [1, 4, 9, 20] {
            let index = ReferenceLatents.startIndex(
                sigmas: try sigmas(steps: steps), strength: 1.0, steps: steps
            )
            #expect(index == 0, "\(steps) steps")
        }
    }

    @Test("the default strength of 0.6 enters two thirds of the way down a nine-step run")
    func defaultStrengthEntersLate() throws {
        let ladder = try sigmas(steps: 9)
        let index = ReferenceLatents.startIndex(sigmas: ladder, strength: 0.6, steps: 9)
        #expect(index == 6, "the first sigma at or below 0.6")
        #expect(ladder[index] <= 0.6)
        #expect(ladder[index - 1] > 0.6, "and the one before it is not")
    }

    @Test("a strength below the whole ladder still runs the last step, never none")
    func zeroStrengthRunsTheLastStep() throws {
        for steps in [1, 4, 9, 20] {
            let index = ReferenceLatents.startIndex(
                sigmas: try sigmas(steps: steps), strength: 0, steps: steps
            )
            #expect(index == steps - 1, "\(steps) steps")
        }
    }

    @Test("the entry point falls as the strength falls, and never leaves the run")
    func startIndexIsMonotonic() throws {
        let ladder = try sigmas(steps: 9)
        let indices = stride(from: Float(1.0), through: 0.0, by: -0.05).map {
            ReferenceLatents.startIndex(sigmas: ladder, strength: $0, steps: 9)
        }
        #expect(indices.allSatisfy { (0..<9).contains($0) })
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $0 <= $1 }, "never goes back up")
    }
}
