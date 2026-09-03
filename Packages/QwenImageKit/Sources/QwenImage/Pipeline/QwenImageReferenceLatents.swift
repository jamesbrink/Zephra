import Foundation
import MLX

/// Where a reference picture joins the denoising loop, and what it joins it with.
///
/// SDEdit: instead of starting from pure noise at the top of the sigma ladder, start partway
/// down, from the picture's latent carrying that rung's share of noise. Both decisions are pure
/// functions of the schedule, which is what lets `VAEEncoderParityTests` and the scheduler
/// suites pin them without weights.
///
/// `ZImage.ReferenceLatents` is the same arithmetic for the other family. The two are kept apart
/// deliberately: one lives inside vendored code that is re-synced against upstream, and the
/// schedules they read are typed differently. Fifteen lines of interpolation is a smaller cost
/// than a dependency edge between a vendored package and ours.
public enum QwenImageReferenceLatents {
    /// The first step whose sigma is at or below `strength`, which is where the loop starts.
    ///
    /// The ladder falls from 1 to nearly 0, so a strength of 1 lands on step 0 and runs
    /// everything — and the mix there is pure noise, so a reference at full strength produces
    /// the text-to-image image exactly. A strength below every rung still runs the last step:
    /// running none would hand the reference straight back.
    ///
    /// `sigmas` may carry the scheduler's trailing zero; only the first `steps` are steps, so
    /// the zero is never chosen.
    public static func startIndex(sigmas: [Double], strength: Double, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        let ladder = sigmas.prefix(steps)
        guard let found = ladder.firstIndex(where: { $0 <= strength }) else { return steps - 1 }
        return min(max(found, 0), steps - 1)
    }

    /// The latent that step starts from: `x_t = (1 - sigma) * x0 + sigma * noise`.
    ///
    /// The same interpolation `FlowMatchEulerScheduler.step` walks back down, which is what
    /// makes resuming partway through exact rather than approximate. The noise is the run's own
    /// seeded noise, so a fixed seed still reproduces the image.
    public static func mixed(reference: MLXArray, noise: MLXArray, sigma: Double) -> MLXArray {
        let level = MLXArray(Float(sigma)).asType(noise.dtype)
        return (MLXArray(Float(1)).asType(noise.dtype) - level) * reference.asType(noise.dtype)
            + level * noise
    }
}
