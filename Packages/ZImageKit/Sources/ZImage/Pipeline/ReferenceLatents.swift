// ZEPHRA-PATCH: SDEdit. Starting the denoise loop partway down the sigma ladder, from a
// reference picture noised to the level that step expects, rather than from pure noise.
//
// The arithmetic is separated from the pipeline on purpose: the two decisions this makes —
// where to enter the loop and what to enter it with — are pure functions of the schedule, and
// a suite can pin them without loading weights or touching Metal.
import Foundation
import MLX

public enum ReferenceLatents {
  /// The first step whose sigma is at or below `strength`, which is where the loop starts.
  ///
  /// The ladder runs from 1 down to nearly 0, so a strength of 1 lands on step 0 and runs
  /// everything (and the mix below is then pure noise, exactly the text-to-image path); a
  /// small strength lands near the end and keeps most of the picture. When nothing on the
  /// ladder is small enough — a strength below the last sigma — the answer is the last step,
  /// because running no steps at all would hand the reference straight back.
  ///
  /// `sigmas` is the scheduler's array including its trailing zero; only the first `steps` of
  /// it are steps, so the zero is never chosen.
  public static func startIndex(sigmas: [Float], strength: Float, steps: Int) -> Int {
    guard steps > 0 else { return 0 }
    let ladder = sigmas.prefix(steps)
    guard let found = ladder.firstIndex(where: { $0 <= strength }) else { return steps - 1 }
    return min(max(found, 0), steps - 1)
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
