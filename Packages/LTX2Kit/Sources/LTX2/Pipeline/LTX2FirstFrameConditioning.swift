import Foundation
import MLX

/// Holding a picture as a clip's first frame: the arithmetic around every step, kept apart from
/// the loop so a suite can check it against the reference without weights or Metal.
///
/// The picture is encoded to one latent frame — the autoencoder is causal, so it has one of its
/// own — and that frame's tokens are held at a conditioning strength `s` from 0 (not held at
/// all) to 1 (held exactly). Everything here follows `pipeline_ltx2_condition.py`:
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
    /// `[1, tokens, 1]`: `strength` over the first latent frame's tokens, zero elsewhere.
    public static func mask(layout: LTX2LatentLayout, strength: Float) -> MLXArray {
        let marked = layout.firstFrameTokens
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
    public static func imposed(_ sample: MLXArray, clean: MLXArray, mask: MLXArray) -> MLXArray {
        MLX.where(mask .>= 1, clean, sample)
    }
}
