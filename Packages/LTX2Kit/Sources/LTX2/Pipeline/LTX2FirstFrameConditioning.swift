import Foundation
import MLX

/// Holding a picture as a clip's first frame: the arithmetic around every step, kept apart from
/// the loop so a suite can check it against the reference without weights or Metal.
///
/// The picture is encoded to one latent frame — the autoencoder is causal, so it has one of its
/// own — and that frame's tokens are held at a conditioning strength `s` from 0 (not held at
/// all) to 1 (held exactly). A run of `1 + 8k` pictures, the end of an earlier clip, is the same
/// arithmetic over `k + 1` latent frames. Everything here follows `pipeline_ltx2_condition.py`:
///
/// - the run starts from `noise * (1 - mask) + clean * mask` rather than from pure noise;
/// - the transformer is told a **per-token** noise level, which is `LTX2Transformer`'s
///   `firstFrameStrength`, not anything in this file;
/// - and each step converts the velocity to the finished-latent estimate at the step's
///   **scalar** sigma, blends the picture into *that*, and converts back. In `x0` space and
///   never in velocity space, which is the one thing the reference's own comment insists on:
///   a velocity is a direction, and mixing two of them does not mix the pictures they point at.
///
/// The reference has no blend *after* the step. This port re-imposes the picture where the mask
/// is exactly 1 and nowhere else, which is not an addition but the same thing the official
/// image-to-video pipeline does by slicing the held frame out of the sample and never stepping
/// it: at strength 1 the frame is meant to survive the ancestral step's fresh noise untouched.
/// A partially held frame is left stepped, as the reference leaves it.
public enum LTX2FirstFrameConditioning {
    /// `[1, tokens, 1]`: `strength` over the first `frames` latent frames' tokens, zero
    /// elsewhere. One frame is a picture held as the first frame; more is a clip carried on
    /// from the end of another, the reference's multi-frame condition at latent index 0.
    public static func mask(layout: LTX2LatentLayout, strength: Float, frames: Int = 1) -> MLXArray {
        let marked = layout.frameTokens(frames)
        return MLX.concatenated(
            [
                MLXArray.full([1, marked, 1], values: MLXArray(strength)),
                MLXArray.zeros([1, layout.tokens - marked, 1]),
            ], axis: 1)
    }

    /// The latent a conditioned run starts from: noise everywhere, the picture where it is held.
    public static func initial(noise: MLXArray, clean: MLXArray, mask: MLXArray) -> MLXArray {
        blended(noise, clean: clean, mask: mask)
    }

    /// `estimate * (1 - mask) + clean * mask`, the blend both ends of a step use.
    public static func blended(_ estimate: MLXArray, clean: MLXArray, mask: MLXArray) -> MLXArray {
        estimate * (1 - mask) + clean * mask
    }

    /// The velocity that carries `sample` to `denoised` at this step's scalar sigma.
    ///
    /// No guard at zero: a step's sigma is one of the eight the schedule walks *from*, and the
    /// only zero on the ladder is the rung it ends at, which no step reads.
    public static func velocity(sample: MLXArray, denoised: MLXArray, sigma: Float) -> MLXArray {
        (sample - denoised) / sigma
    }

    /// The picture put back where the mask is exactly 1, after the step has moved everything.
    /// A mask that holds nothing at full strength leaves the sample alone.
    ///
    /// `mask .>= 1` is an exact float comparison on purpose, not a tolerance the reference
    /// happens to need: re-imposing is meant only for the frame held exactly, which is
    /// `strength == 1` here and the interface's `referenceStrength == 0` before
    /// `LTX2RequestMapper` inverts it — the default, and the one end of the slider a person
    /// picks by landing on it rather than by arithmetic that could round short. `1 - 0` is exact
    /// in floating point, so that mask is exactly 1 with no accumulated error to guard against,
    /// and the slider's other steps (0.05 apart, `referenceStrengthBounds: 0.0...0.9`) land at
    /// `strength` no closer to 1 than 0.95, comfortably clear of this comparison.
    public static func imposed(_ sample: MLXArray, clean: MLXArray, mask: MLXArray) -> MLXArray {
        MLX.where(mask .>= 1, clean, sample)
    }
}
