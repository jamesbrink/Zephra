// ZEPHRA-PATCH: SDEdit. Starting the denoise loop partway down the sigma ladder, from a
// reference picture noised to the level that step expects, rather than from pure noise.
//
// The arithmetic is separated from the pipeline on purpose: the two decisions this makes —
// where to enter the loop and what to enter it with — are pure functions of the schedule, and
// a suite can pin them without loading weights or touching Metal.
import Foundation
import MLX

public enum ReferenceLatents {
  /// Where in the run to start, for a strength between zero and one.
  ///
  /// Strength buys a *share of the steps*, not a noise level: `steps * strength` steps run,
  /// truncated and never fewer than one, and the loop enters that far from the end. Reading it
  /// as a share is what diffusers' image-to-image pipelines do in `get_timesteps`, and the
  /// reason to follow that rather than to look up the first sigma at or below the strength is
  /// that a distilled ladder is not evenly spaced. Qwen-Image's four steps are 1.0, 0.767,
  /// 0.456 and 0.02: every strength from 0.1 to 0.4 would find that 0.02 first, run a single
  /// step from almost no noise, and hand the picture back unchanged.
  ///
  /// The rounding is a deliberate departure from `get_timesteps`, which takes the ceiling of
  /// the share. Truncating is the only mapping under which every strength the slider offers
  /// keeps some of the picture. So 0.9 of nine steps enters at 1 and runs 8; 0.6 of nine
  /// enters at 4 and runs 5; 0.1 of nine enters at 8 and runs the last one alone. On a short
  /// ladder it is the whole top of the range: 0.8 of four steps is 3.2 and 0.9 is 3.6, and the
  /// ceiling of both is four — an entry of 0, pure noise, the picture discarded — where
  /// truncated both run three from the second rung. So the entry is 0 only at a strength of
  /// exactly 1, which is the text-to-image path, and that is why a model that reads a picture
  /// keeps its upper bound below 1: the bound is a floor on how much of the picture survives,
  /// and how much a tenth of strength is worth depends on how many steps the model runs.
  ///
  /// The strength is nudged up by a hair before the product is truncated. A `Float` carries
  /// up to six parts in a hundred million of rounding, so 0.7 arrives as 0.69999999 and ten
  /// steps of it come to 6.9999999, which would buy six; a nudge of 1e-7 on the strength
  /// clears that at any step count, and a whole-number share is never nearer than 0.05 to the
  /// one below at the slider's granularity, so the nudge cannot promote a share that was
  /// really short.
  ///
  /// The sigma ladder is not consulted here; the caller reads `sigmas[startIndex]` for the mix.
  public static func startIndex(strength: Float, steps: Int) -> Int {
    guard steps > 0 else { return 0 }
    // ZEPHRA-PATCH: truncate robustly, in doubles; see the doc comment above.
    let requested = Int((Double(steps) * (Double(strength) + 1e-7)).rounded(.down))
    let running = min(max(requested, 1), steps)
    return steps - running
  }

  /// The latent that step starts from: the encoded reference carrying that step's share of
  /// noise, `x_t = (1 - sigma) * x0 + sigma * noise`.
  ///
  /// This is the same interpolation the scheduler's `step` walks back down, which is what makes
  /// resuming partway through legitimate rather than approximate. The noise is the run's own
  /// seeded noise, so a fixed seed still reproduces the image exactly.
  public static func mixed(reference: MLXArray, noise: MLXArray, sigma: Float) -> MLXArray {
    let sigmaArray = MLXArray(sigma).asType(noise.dtype)
    return (MLXArray(1 as Float).asType(noise.dtype) - sigmaArray) * reference.asType(noise.dtype)
      + sigmaArray * noise
  }
}
