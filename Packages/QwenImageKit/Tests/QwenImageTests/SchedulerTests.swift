import Foundation
import MLX
import Testing

@testable import QwenImage

/// The noise ladder. Every property here is one a wrong schedule still satisfies loosely, so
/// they are asserted exactly.
@Suite("Flow-match scheduler")
struct SchedulerTests {
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

    @Test("the schedule ends on the configured terminal sigma, then a zero")
    func terminalShiftLandsWhereItSays() {
        let scheduler = FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: 4, imageSequenceLength: 4096)
        #expect(scheduler.sigmas.count == 5)
        #expect(scheduler.sigmas.last == 0)
        let terminal = try! #require(scheduler.sigmas.dropLast().last)
        #expect(abs(terminal - 0.02) < 1e-9, "shift_terminal is what the tail is stretched to")
    }

    @Test("sigmas fall from one, step by step, and never rise")
    func monotonic() {
        let scheduler = FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: 8, imageSequenceLength: 4096)
        #expect(abs(scheduler.sigmas[0] - 1) < 1e-9, "the first step starts from pure noise")
        for (earlier, later) in zip(scheduler.sigmas, scheduler.sigmas.dropFirst()) {
            #expect(later < earlier)
        }
    }

    @Test("a bigger image is held at high noise for longer")
    func dynamicShiftFollowsImageSize() {
        let small = FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: 8, imageSequenceLength: 1024)
        let large = FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: 8, imageSequenceLength: 4096)
        // Same endpoints, but the large image's ladder sits above the small one in between.
        for index in 1..<7 {
            #expect(large.sigmas[index] > small.sigmas[index])
        }
    }

    @Test("a step keeps the sample's dtype")
    func stepKeepsDtype() {
        // The Euler step is `sample + prediction * (sigma_next - sigma)`, the gap a Swift
        // scalar. MLX promotes a scalar to the array's dtype, so a bfloat16 sample steps to a
        // bfloat16 sample; a float32 gap array here would widen every step of the loop.
        let scheduler = FlowMatchEulerScheduler(
            configuration: Self.configuration, steps: 4, imageSequenceLength: 4096)
        let sample = MLXArray([0.5, -0.25, 1, 2] as [Float], [1, 4]).asType(.bfloat16)
        let prediction = MLXArray([1, 1, -1, 0.5] as [Float], [1, 4]).asType(.bfloat16)
        let stepped = scheduler.step(modelOutput: prediction, index: 0, sample: sample)
        #expect(stepped.dtype == .bfloat16)
        let wide = scheduler.step(
            modelOutput: prediction.asType(.float32), index: 0, sample: sample.asType(.float32))
        #expect(wide.dtype == .float32)
    }

    @Test("mu runs through the two published points")
    func muInterpolatesTheConfiguredLine() {
        #expect(
            abs(DynamicShift.mu(imageSequenceLength: 256, configuration: Self.configuration) - 0.5)
                < 1e-9)
        #expect(
            abs(DynamicShift.mu(imageSequenceLength: 8192, configuration: Self.configuration) - 0.9)
                < 1e-9)
    }
}
