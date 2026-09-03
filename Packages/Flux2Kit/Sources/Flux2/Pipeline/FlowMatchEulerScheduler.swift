import Foundation
import MLX

/// The flow-matching noise schedule, and the one-line Euler update that walks it.
///
/// The ladder is bent by a shift that depends on the image's token count and the step count,
/// then a zero is appended so the final step arrives at a clean sample. klein's config sets no
/// terminal value, so nothing stretches the tail; the field is honoured anyway, because a
/// future release of the same architecture may set one.
public struct FlowMatchEulerScheduler: Sendable {
    /// The noise level at each step, with a trailing zero. One longer than the step count.
    public let sigmas: [Double]

    /// Builds the schedule for one generation.
    ///
    /// - Parameters:
    ///   - configuration: The published scheduler settings.
    ///   - steps: How many denoising steps to take.
    ///   - imageSequenceLength: Tokens in the image being made, which sets the shift.
    public init(
        configuration: Flux2SchedulerConfiguration,
        steps: Int,
        imageSequenceLength: Int
    ) {
        // Evenly spaced in sigma from one down to 1/steps: the ladder the reference pipeline
        // hands its scheduler. The scheduler's own default is spaced in timesteps and ends near
        // zero instead, and no klein image was ever made with it.
        var values = (0..<steps).map { step -> Double in
            guard steps > 1 else { return 1 }
            return 1 - Double(step) * (1 - 1 / Double(steps)) / Double(steps - 1)
        }

        if configuration.useDynamicShifting {
            let mu = EmpiricalShift.mu(imageSequenceLength: imageSequenceLength, steps: steps)
            values = values.map { Self.shifted($0, mu: mu) }
        }

        if let terminal = configuration.shiftTerminal, let last = values.last {
            values = Self.stretched(values, from: last, to: terminal)
        }

        sigmas = values + [0]
    }

    /// The timestep the transformer is told at each step: the sigma, which the model scales
    /// by a thousand itself.
    public var timesteps: [Double] { Array(sigmas.dropLast()) }

    /// One Euler step: move along the probability flow by the gap to the next noise level.
    public func step(modelOutput: MLXArray, index: Int, sample: MLXArray) -> MLXArray {
        sample + modelOutput * Float(sigmas[index + 1] - sigmas[index])
    }

    /// The exponential time shift.
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
