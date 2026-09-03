import Foundation
import MLX

/// The flow-matching noise schedule, and the one-line Euler update that walks it.
///
/// Three things happen to the sigmas before a step is ever taken, and all three are silent when
/// wrong: the ladder is bent by a shift that depends on the image's token count, the tail is
/// stretched so the last sigma lands on a configured terminal value, and a zero is appended so
/// the final step arrives at a clean sample. Qwen-Image-2512 sets `shift_terminal`, which older
/// flow-matching schedulers have no notion of; dropping it changes every sigma.
public struct FlowMatchEulerScheduler: Sendable {
    /// The noise level at each step, with a trailing zero. One longer than the step count.
    public let sigmas: [Double]

    /// Builds the schedule for one generation.
    ///
    /// - Parameters:
    ///   - configuration: The published scheduler settings.
    ///   - steps: How many denoising steps to take.
    ///   - imageSequenceLength: Patch tokens in the image, which sets the dynamic shift.
    public init(
        configuration: QwenImageSchedulerConfiguration,
        steps: Int,
        imageSequenceLength: Int
    ) {
        // Evenly spaced in sigma from one down to 1/steps: the ladder the reference pipeline
        // hands its scheduler, and the one the four-step adapter was distilled against. The
        // scheduler's own default is spaced in timesteps and ends near zero instead, and no
        // Qwen-Image image was ever made with it.
        var values = (0..<steps).map { step -> Double in
            guard steps > 1 else { return 1 }
            return 1 - Double(step) * (1 - 1 / Double(steps)) / Double(steps - 1)
        }

        if configuration.useDynamicShifting {
            let mu = DynamicShift.mu(
                imageSequenceLength: imageSequenceLength, configuration: configuration)
            values = values.map { Self.shifted($0, mu: mu) }
        } else if configuration.shift != 1 {
            let shift = configuration.shift
            values = values.map { shift * $0 / (1 + (shift - 1) * $0) }
        }

        if let terminal = configuration.shiftTerminal, let last = values.last {
            values = Self.stretched(values, from: last, to: terminal)
        }

        sigmas = values + [0]
    }

    /// One Euler step: move along the probability flow by the gap to the next noise level.
    public func step(modelOutput: MLXArray, index: Int, sample: MLXArray) -> MLXArray {
        sample + modelOutput * Float(sigmas[index + 1] - sigmas[index])
    }

    /// The exponential time shift. `sigma` in the reference is 1 for this model, so it is folded
    /// away rather than carried as a parameter nothing varies.
    private static func shifted(_ sigma: Double, mu: Double) -> Double {
        let scale = exp(mu)
        return scale / (scale + (1 / sigma - 1))
    }

    /// Rescales the ladder so its last rung lands on `terminal` while the first stays put.
    private static func stretched(
        _ values: [Double], from last: Double, to terminal: Double
    ) -> [Double] {
        let scale = (1 - last) / (1 - terminal)
        guard scale != 0 else { return values }
        return values.map { 1 - (1 - $0) / scale }
    }
}
