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
    /// Where in the run to start, for a strength between zero and one.
    ///
    /// Strength buys a *share of the steps*, not a noise level: `steps * strength` steps run,
    /// rounded and never fewer than one, and the loop enters that far from the end. This is the
    /// mapping diffusers' image-to-image pipelines use in `get_timesteps`, and this model is
    /// exactly why it is the right one. Its four distilled steps are 1.0, 0.767, 0.456 and
    /// 0.02, so picking the first sigma at or below the strength would send every strength from
    /// 0.1 to 0.4 to that 0.02 — one step from almost no noise, and the picture handed back
    /// unchanged.
    ///
    /// So 0.6 of four steps enters at 2 and runs 2; 0.9 of four rounds up to all four, which
    /// enters at 0, where the mix below is pure noise and the reference contributes nothing.
    /// A reference at full strength is exactly the text-to-image path.
    ///
    /// The sigma ladder is not consulted here; the caller reads `sigmas[startIndex]` for the mix.
    public static func startIndex(strength: Double, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        let requested = Int((Double(steps) * strength).rounded())
        let running = min(max(requested, 1), steps)
        return steps - running
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
