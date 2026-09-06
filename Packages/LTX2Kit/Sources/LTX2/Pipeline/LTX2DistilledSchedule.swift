import Foundation
import MLX

/// The distilled transformer's fixed schedule and its ancestral Euler step.
///
/// LTX-2.5's distilled checkpoint runs nine sigmas as eight steps, with no guidance and no
/// shift: the list is literal and the only transform is the `× 1000` the timestep embedding
/// applies. Since 2.5 the step is Euler-ancestral in the rectified-flow parameterisation
/// (`alpha = 1 - sigma`), not the DDIM helper: each step moves towards the denoised estimate
/// and re-noises with fresh noise scaled so the marginal stays on the schedule. With `eta` 1
/// the intermediate `sigmaDown` is `sigmaNext² / sigma`, and the last step, to sigma 0, is a
/// pure read-out of the estimate.
public struct LTX2DistilledSchedule: Sendable, Hashable {
    /// The nine sigmas the distilled transformer was trained to walk, first stage.
    public static let sigmas: [Double] = [
        1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0,
    ]

    /// How much of the schedule's noise is re-drawn at each step; 1 is what the reference runs.
    public var eta: Double
    /// A multiplier on the re-drawn noise; 1 is what the reference runs.
    public var noiseScale: Double

    /// Creates the schedule with the reference's ancestral settings.
    public init(eta: Double = 1, noiseScale: Double = 1) {
        self.eta = eta
        self.noiseScale = noiseScale
    }

    /// Steps in a run: one fewer than the sigmas.
    public var steps: Int { Self.sigmas.count - 1 }

    /// The model's estimate of the finished latent from the sample and its velocity, which is
    /// what the preview shows and what the last step hands back.
    public static func denoised(_ sample: MLXArray, velocity: MLXArray, sigma: Double) -> MLXArray {
        sample - velocity * Float(sigma)
    }

    /// One ancestral Euler step from `Self.sigmas[index]` to `Self.sigmas[index + 1]`.
    ///
    /// `noise` is a fresh standard-normal draw of the sample's shape; it is ignored on the last
    /// step, whose answer is the denoised estimate itself.
    public func step(sample: MLXArray, velocity: MLXArray, index: Int, noise: MLXArray) -> MLXArray {
        let sigma = Self.sigmas[index]
        let sigmaNext = Self.sigmas[index + 1]
        let denoised = Self.denoised(sample, velocity: velocity, sigma: sigma)
        guard sigmaNext > 0 else { return denoised }
        let terms = Self.ancestralTerms(sigma: sigma, sigmaNext: sigmaNext, eta: eta)
        let interpolated = sample * Float(terms.ratio) + denoised * Float(1 - terms.ratio)
        return interpolated * Float(terms.alphaRatio) + noise * Float(noiseScale * terms.renoise)
    }

    /// The scalar arithmetic of one ancestral step, kept apart from the arrays so it can be
    /// checked against the reference to the last digit.
    static func ancestralTerms(sigma: Double, sigmaNext: Double, eta: Double)
        -> (ratio: Double, alphaRatio: Double, renoise: Double)
    {
        let downstep = 1 + (sigmaNext / sigma - 1) * eta
        let sigmaDown = sigmaNext * downstep
        let ratio = sigmaDown / sigma
        let alphaNext = 1 - sigmaNext
        let alphaDown = 1 - sigmaDown
        let variance = sigmaNext * sigmaNext
            - sigmaDown * sigmaDown * alphaNext * alphaNext / (alphaDown * alphaDown)
        return (ratio, alphaNext / alphaDown, variance.squareRoot().isNaN ? 0 : max(variance, 0).squareRoot())
    }
}
