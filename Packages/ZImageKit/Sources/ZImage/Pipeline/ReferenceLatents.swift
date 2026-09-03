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
  /// rounded and never fewer than one, and the loop enters that far from the end. This is the
  /// mapping diffusers' image-to-image pipelines use in `get_timesteps`, and the reason to
  /// follow it rather than to look up the first sigma at or below the strength is that a
  /// distilled ladder is not evenly spaced. Qwen-Image's four steps are 1.0, 0.767, 0.456 and
  /// 0.02: every strength from 0.1 to 0.4 would find that 0.02 first, run a single step from
  /// almost no noise, and hand the picture back unchanged.
  ///
  /// So 0.9 of nine steps enters at 1 and runs 8; 0.6 of nine enters at 4 and runs 5; 0.1 of
  /// nine enters at 8 and runs the last one alone. At a strength of 1 the entry is 0, where the
  /// mix below is pure noise and the reference contributes nothing — a reference at full
  /// strength is exactly the text-to-image path, which is why the models' bounds stop at 0.9.
  ///
  /// The sigma ladder is not consulted here; the caller reads `sigmas[startIndex]` for the mix.
  public static func startIndex(strength: Float, steps: Int) -> Int {
    guard steps > 0 else { return 0 }
    let requested = Int((Float(steps) * strength).rounded())
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
