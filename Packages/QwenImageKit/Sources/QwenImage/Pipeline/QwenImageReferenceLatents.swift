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
    /// truncated and never fewer than one, and the loop enters that far from the end. Reading
    /// it as a share rather than as a noise level is what diffusers' image-to-image pipelines
    /// do in `get_timesteps`, and this model is exactly why: its four distilled steps are 1.0,
    /// 0.767, 0.456 and 0.02, so picking the first sigma at or below the strength would send
    /// every strength from 0.1 to 0.4 to that 0.02 — one step from almost no noise, and the
    /// picture handed back unchanged.
    ///
    /// The rounding is a deliberate departure from `get_timesteps`, which takes the ceiling
    /// of the share. Truncating is the only mapping under which every strength the slider
    /// offers keeps some of the picture: 0.6 of four steps enters at 2 and runs 2 either
    /// way, but 0.8 of four is 3.2 and 0.9 is 3.6, and the ceiling of both is four — entry
    /// 0, where the mix below is pure noise and the picture is silently discarded at the top
    /// of the range the model offers. Truncated, both run three from an entry of 1. The entry
    /// is 0 only at a strength of exactly 1, which is the text-to-image path, and is why the
    /// upper bound stays below it.
    ///
    /// The product is nudged up by a hair before truncating, because `Double` arithmetic lands
    /// `100 * 0.29` at 28.999999999999996, and a strength that means twenty-nine steps must
    /// not buy twenty-eight. A whole-number share is never nearer than 0.01 to the one
    /// below, so the nudge cannot promote a share that was really short.
    ///
    /// The sigma ladder is not consulted here; the caller reads `sigmas[startIndex]` for the mix.
    public static func startIndex(strength: Double, steps: Int) -> Int {
        guard steps > 0 else { return 0 }
        let requested = Int((Double(steps) * strength + 1e-9).rounded(.down))
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
