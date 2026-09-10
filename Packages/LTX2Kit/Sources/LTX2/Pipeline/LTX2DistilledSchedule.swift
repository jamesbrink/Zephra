import Foundation
import MLX

/// The distilled transformer's fixed schedules and their ancestral Euler step.
///
/// LTX-2.5's distilled checkpoint runs nine sigmas as eight steps, with no guidance and no
/// shift: the list is literal and the only transform is the `× 1000` the timestep embedding
/// applies. A two-stage run walks a second, shorter ladder over the upsampled latent, entering
/// it by noising that latent to the ladder's first sigma (`noised`) and then stepping as
/// before. Since 2.5 the step is Euler-ancestral in the rectified-flow parameterisation
/// (`alpha = 1 - sigma`), not the DDIM helper: each step moves towards the denoised estimate
/// and re-noises with fresh noise scaled so the marginal stays on the schedule. With `eta` 1
/// the intermediate `sigmaDown` is `sigmaNext² / sigma`, and the last step, to sigma 0, is a
/// pure read-out of the estimate.
public struct LTX2DistilledSchedule: Sendable, Hashable {
    /// The nine sigmas the distilled transformer was trained to walk over a fresh latent.
    public static let firstStage: [Double] = [
        1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0,
    ]

    /// The four sigmas the second stage walks over the upsampled latent, three steps, entering
    /// at the first stage's sixth rung.
    public static let secondStage: [Double] = [0.909375, 0.725, 0.421875, 0.0]


    /// The ladder this schedule walks, first sigma to last.
    public let sigmas: [Double]
    /// How much of the schedule's noise is re-drawn at each step; 1 is what the reference runs.
    public var eta: Double
    /// A multiplier on the re-drawn noise; 1 is what the reference runs.
    public var noiseScale: Double

    /// Creates a schedule over `sigmas`, the first stage unless another ladder is given, with
    /// the reference's ancestral settings.
    public init(sigmas: [Double] = Self.firstStage, eta: Double = 1, noiseScale: Double = 1) {
        self.sigmas = sigmas
        self.eta = eta
        self.noiseScale = noiseScale
    }

    /// Steps in a run: one fewer than the sigmas.
    public var steps: Int { sigmas.count - 1 }

    /// The model's estimate of the finished latent from the sample and its velocity, which is
    /// what the preview shows and what the last step hands back.
    public static func denoised(_ sample: MLXArray, velocity: MLXArray, sigma: Double) -> MLXArray {
        sample - velocity * Float(sigma)
    }

    /// `latent` noised to the ladder's first sigma, which is how a later stage enters the
    /// schedule over a latent it was handed: plain flow-match noising,
    /// `noise · sigma + latent · (1 - sigma)`, the reference's `_create_noised_state`.
    ///
    /// `noise` is a fresh standard-normal draw of the latent's shape.
    public func noised(_ latent: MLXArray, noise: MLXArray) -> MLXArray {
        let sigma = Float(sigmas[0])
        return noise * sigma + latent * (1 - sigma)
    }

    /// One ancestral Euler step from `sigmas[index]` to `sigmas[index + 1]`.
    ///
    /// `noise` is a fresh standard-normal draw of the sample's shape; it is ignored on the last
    /// step, whose answer is the denoised estimate itself.
    public func step(sample: MLXArray, velocity: MLXArray, index: Int, noise: MLXArray) -> MLXArray {
        let sigma = sigmas[index]
        let sigmaNext = sigmas[index + 1]
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
