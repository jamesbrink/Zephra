import Foundation
import MLX
import ZephraMLX

/// Everything the denoising loop needs that does not change from step to step.
///
/// A side is one forward pass's worth: the conditioning the transformer reads, the joint layout
/// the encoder's slot mask and the image grids imply, and the rotary table over that layout.
/// Classifier-free guidance is a second side, and it is genuinely a second everything — a
/// negative prompt is a different length, so its joint sequence and its rotary table are its
/// own, and so is its prefix cache.
struct QwenImage21Conditioning {
    /// One forward pass's fixed inputs.
    struct Side {
        /// `[1, encoderTokens, contextInDim]` in the stream's dtype.
        let text: MLXArray
        /// How text and latents interleave for this prompt.
        let layout: QwenImage21JointLayout
        /// The rotary table over the whole joint sequence.
        let frequencies: RotaryFrequencies
    }

    /// The prompt.
    let positive: Side
    /// The negative prompt, when guidance is above one and there is one.
    let negative: Side?
    /// Every reference picture's latent, normalised and packed, `[1, conditionTokens, zDim]` in
    /// the stream's dtype — or nil with no references. Prepended to the noise on every step.
    let conditionTokens: MLXArray?
    /// Latent rows of the picture being made.
    let latentHeight: Int
    /// Latent columns of it.
    let latentWidth: Int

    /// Latent tokens the picture being made occupies, which is what the schedule's shift and
    /// the prediction's tail slice are both counted in.
    var targetTokens: Int { latentHeight * latentWidth }
}
