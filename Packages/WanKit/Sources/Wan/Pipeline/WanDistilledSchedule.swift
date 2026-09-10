import Foundation
import MLX

/// The distilled transformer's three-step schedule and its denoise-and-renoise step.
///
/// FastWan2.2-TI2V-5B runs three steps at timesteps 1000, 757 and 522, read off the grid
/// diffusers' `FlowMatchEulerDiscreteScheduler(shift: 8)` builds over its thousand training
/// timesteps: sigmas from 1 down to 1/1000, each shifted `8s / (1 + 7s)`, timesteps a thousand
/// times that. Not every step's timestep is on the grid, so a step's sigma is the grid entry
/// whose timestep is nearest. Each step reads the model's velocity as the finished latent,
/// `x0 = x - sigma * v`, and, when a step follows, puts fresh noise back at the next sigma,
/// `x = (1 - sigmaNext) * x0 + sigmaNext * noise`, which is the scheduler's own forward
/// process; the last step's estimate is the answer. No guidance.
public struct WanDistilledSchedule: Sendable, Hashable {
    /// The shift the grid was built with.
    public static let shift: Double = 8
    /// Training timesteps, and the grid's length.
    public static let trainingTimesteps = 1000
    /// The three timesteps the distilled transformer was trained to walk.
    public static let timesteps: [Double] = [1000, 757, 522]

    /// The grid's sigmas, from 1 down to `shift / (1000 + shift - 1)`.
    public static let sigmas: [Double] = (0..<trainingTimesteps).map { index in
        let sigma = Double(trainingTimesteps - index) / Double(trainingTimesteps)
        return shift * sigma / (1 + (shift - 1) * sigma)
    }

    /// The grid's timesteps, `sigmas` times a thousand.
    public static let gridTimesteps: [Double] = sigmas.map { $0 * Double(trainingTimesteps) }

    /// Creates the schedule.
    public init() {}

    /// Steps in a run.
    public var steps: Int { Self.timesteps.count }

    /// The sigma of the grid entry whose timestep is nearest `timestep`.
    public static func sigma(forTimestep timestep: Double) -> Double {
        let nearest = gridTimesteps.indices.min { abs(gridTimesteps[$0] - timestep) < abs(gridTimesteps[$1] - timestep) }!
        return sigmas[nearest]
    }

    /// The sigma of step `index`.
    public func sigma(at index: Int) -> Double {
        Self.sigma(forTimestep: Self.timesteps[index])
    }

    /// The model's estimate of the finished latent from the sample and its velocity, which is
    /// what the preview shows and what the last step hands back.
    public static func denoised(_ sample: MLXArray, velocity: MLXArray, sigma: Double) -> MLXArray {
        sample - velocity * Float(sigma)
    }

    /// One step from `Self.timesteps[index]` to the next: the denoised estimate, re-noised at
    /// the next step's sigma with `noise`, a fresh standard-normal draw of the sample's shape.
    /// On the last step `noise` is ignored and the estimate itself is the answer.
    public func step(sample: MLXArray, velocity: MLXArray, index: Int, noise: MLXArray) -> MLXArray {
        let denoised = Self.denoised(sample, velocity: velocity, sigma: sigma(at: index))
        guard index + 1 < steps else { return denoised }
        let sigmaNext = Float(sigma(at: index + 1))
        return denoised * (1 - sigmaNext) + noise * sigmaNext
    }
}
