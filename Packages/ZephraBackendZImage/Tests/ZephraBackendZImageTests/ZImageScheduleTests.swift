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
    func fullStrengthStartsAtZero() {
        for steps in [1, 4, 9, 20] {
            #expect(ReferenceLatents.startIndex(strength: 1, steps: steps) == 0, "\(steps) steps")
        }
    }

    @Test("strength is a share of the steps, not a noise level")
    func startIndexIsAShareOfTheSteps() {
        // 9 * 0.6 = 5.4, so five of the nine steps run and the loop enters at 4.
        #expect(ReferenceLatents.startIndex(strength: 0.6, steps: 9) == 4)
        #expect(ReferenceLatents.startIndex(strength: 0.9, steps: 9) == 1, "8.1 truncates to 8")
        // Truncated, not rounded: 4.5 buys four steps, not five. (diffusers' `get_timesteps`
        // would ceil it to five; the departure is deliberate, see the table below.)
        #expect(ReferenceLatents.startIndex(strength: 0.5, steps: 9) == 5)
        #expect(
            ReferenceLatents.startIndex(strength: 0.1, steps: 9) == 8,
            "0.9 truncates to none, and the floor of one step applies")
    }

    @Test("a strength too small to buy a whole step still buys one, never none")
    func tinyStrengthRunsTheLastStep() {
        // 4 * 0.1 is 0.4, which truncates to nothing; running no steps would hand the picture
        // back untouched, so one step is the floor.
        #expect(ReferenceLatents.startIndex(strength: 0.1, steps: 4) == 3)
        #expect(ReferenceLatents.startIndex(strength: 0, steps: 9) == 8)
    }

    /// The floor column of the audit's table, at the two ladders the catalog ships. Ceil —
    /// diffusers' `get_timesteps` — would put 0.8 and 0.9 of four steps at entry 0, and 0.9 of
    /// nine there too; both discard the picture at the top of the slider.
    @Test(
        "the entry step is the same under every strength the slider offers, at 9 and 4 steps",
        arguments: [
            (Float(0.1), 8, 3), (0.2, 8, 3), (0.3, 7, 3), (0.4, 6, 3), (0.5, 5, 2),
            (0.6, 4, 2), (0.7, 3, 2), (0.8, 2, 1), (0.9, 1, 1),
        ])
    func entryTable(strength: Float, atNine: Int, atFour: Int) {
        #expect(ReferenceLatents.startIndex(strength: strength, steps: 9) == atNine)
        #expect(ReferenceLatents.startIndex(strength: strength, steps: 4) == atFour)
    }

    @Test("a product that lands a hair under a whole number is not truncated below it")
    func epsilonGuard() {
        // A Float 0.7 is 0.69999999, so ten steps of it come to 6.9999999 in doubles; seven
        // steps must not buy six. Twenty steps of it are the same case at the top of the
        // model's range.
        #expect(Double(Float(0.7)) * 10 < 7, "the arithmetic really does land short")
        #expect(ReferenceLatents.startIndex(strength: 0.7, steps: 10) == 3)
        #expect(ReferenceLatents.startIndex(strength: 0.7, steps: 20) == 6)
        // And a share that is really short stays short: 0.65 of ten is 6.5, six steps.
        #expect(ReferenceLatents.startIndex(strength: 0.65, steps: 10) == 4)
    }

    @Test("the ladder is not consulted: the same strength lands the same way at every size")
    func entryDoesNotDependOnTheLadder() throws {
        // The point of the share mapping. Z-Image's ladder is bent by a shift of 3, so its
        // sigmas at 9 steps are nowhere near evenly spaced, yet 0.6 buys five steps regardless.
        let ladder = try sigmas(steps: 9)
        #expect(ladder[4] > 0.7, "the entry sigma is a real noise level, not the ladder's tail")
        #expect(ReferenceLatents.startIndex(strength: 0.6, steps: 9) == 4)
    }

    @Test("the entry point falls as the strength rises, and never leaves the run")
    func startIndexIsMonotonic() {
        let indices = stride(from: Float(0), through: 1, by: 0.05).map {
            ReferenceLatents.startIndex(strength: $0, steps: 9)
        }
        #expect(indices.allSatisfy { (0..<9).contains($0) })
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $0 >= $1 }, "never goes back down")
    }
}
