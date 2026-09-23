import Foundation
import MLX

/// The flow-matching noise schedule, and the one-line Euler update that walks it.
///
/// Four things happen to the sigmas before a step is ever taken, and all four are silent when
/// wrong: the ladder starts evenly spaced from one down to `1/steps` rather than at the
/// scheduler's own default spacing; it is bent by a shift that depends on the image's token
/// count; the tail is stretched so the last sigma lands on `shiftTerminal`, which is 0.02 here
/// and not zero; and a zero is appended so the final step arrives at a clean sample.
///
/// The timestep the transformer is told is the sigma times `numTrainTimesteps`, which the
/// reference pipeline then divides by a thousand again on the way in. Both numbers are exposed
/// because the fixture dumps both and a port that conflates them is off by a factor of a
/// thousand in exactly one place.
public struct QwenImage21Schedule: Sendable {
    /// The noise level at each step, with a trailing zero. One longer than the step count.
    public let sigmas: [Double]

    /// The scheduler's `num_train_timesteps`, which scales a sigma into a timestep.
    private let trainTimesteps: Int

    /// Builds the schedule for one generation.
    ///
    /// - Parameters:
    ///   - configuration: The published scheduler settings.
    ///   - steps: How many denoising steps to take.
    ///   - imageSequenceLength: Latent tokens in the image being made — one per latent cell,
    ///     since 2.1 does not patchify — which sets the dynamic shift.
    public init(
        configuration: QwenImage21SchedulerConfiguration,
        steps: Int,
        imageSequenceLength: Int
    ) {
        // `np.linspace(1.0, 1 / steps, steps)`: the ladder the reference pipeline hands its
        // scheduler. The scheduler's own default is spaced in timesteps and ends near zero
        // instead, and no Qwen-Image 2.1 picture was ever made with it.
        var values = (0..<steps).map { step -> Double in
            guard steps > 1 else { return 1 }
            return 1 - Double(step) * (1 - 1 / Double(steps)) / Double(steps - 1)
        }

        if configuration.useDynamicShifting {
            let mu = QwenImage21DynamicShift.mu(
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
        trainTimesteps = configuration.numTrainTimesteps
    }

    /// What the reference passes the transformer at each step, before its own division by a
    /// thousand: the sigma scaled by `num_train_timesteps`.
    public var timesteps: [Double] { sigmas.dropLast().map { $0 * Double(trainTimesteps) } }

    /// One Euler step: move along the probability flow by the gap to the next noise level.
    /// `stochastic_sampling` is false for this model, so there is no second term.
    public func step(modelOutput: MLXArray, index: Int, sample: MLXArray) -> MLXArray {
        sample + modelOutput * Float(sigmas[index + 1] - sigmas[index])
    }

    /// The exponential time shift. `sigma` in the reference is 1 for this model, so it is
    /// folded away rather than carried as a parameter nothing varies.
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
