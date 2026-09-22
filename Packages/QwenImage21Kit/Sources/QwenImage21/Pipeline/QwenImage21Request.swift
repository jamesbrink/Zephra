import Foundation
import MLX

/// One picture, as the pipeline is asked for it.
///
/// Plain values, so it crosses from the engine's world to the pipeline's without carrying an
/// array along: a reference picture arrives as encoded bytes and is decoded, fitted and
/// composited inside the pipeline, where the size it is brought to is decided. That is the
/// shape `Flux2GenerationRequest` uses and the shape the engine already holds a reference in —
/// `GenerationSettings.referenceImage` is PNG bytes — so nothing on the way in has to make an
/// `MLXArray` that the fit would immediately resample anyway.
///
/// The one exception is `noise`, which exists for the parity harness alone: `Tools`' reference
/// dump saves the latent `randn` it drew, and a Swift run that injects it is comparable to the
/// reference's own step for step. Left nil, the loop draws its own from `seed`.
public struct QwenImage21Request {
    /// What the picture should show.
    public var prompt: String
    /// What it should not. Read only when `guidance` is above one; the reference's
    /// `true_cfg_scale` defaults to 1 and 2.1 is meant to be sampled without guidance.
    public var negativePrompt: String
    /// Rendered width in pixels, a multiple of the size alignment (32).
    public var width: Int
    /// Rendered height in pixels.
    public var height: Int
    /// Denoising steps. Forty is the reference pipeline's default.
    public var steps: Int
    /// `true_cfg_scale`. One, or anything at or below one, runs a single forward per step.
    public var guidance: Double
    /// The noise seed.
    public var seed: UInt64
    /// Reference pictures, as encoded bytes — PNG, JPEG, anything ImageIO reads. Each is
    /// brought to `calculate_dimensions(1024², its own aspect)` once, and that one resize feeds
    /// both the vision tower (flattened over white) and the autoencoder (all four channels).
    /// The model card allows up to ten.
    public var references: [Data]
    /// The latent tile edge the autoencoder decodes in, or nil for the exact, untiled decode.
    /// Measured: the approximation is coarse below about twelve cells. See `PROVENANCE.md`.
    public var vaeTile: Int?
    /// Noise the loop starts from, `[1, tokens, zDim]` in the transformer's packed space,
    /// instead of the seed's own. For the parity harness; nil everywhere else.
    public var noise: MLXArray?

    /// Creates a request.
    public init(
        prompt: String,
        negativePrompt: String = "",
        width: Int,
        height: Int,
        steps: Int,
        guidance: Double = 1,
        seed: UInt64,
        references: [Data] = [],
        vaeTile: Int? = nil,
        noise: MLXArray? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.guidance = guidance
        self.seed = seed
        self.references = references
        self.vaeTile = vaeTile
        self.noise = noise
    }

    /// Whether this request runs the second, negative forward: the reference's
    /// `true_cfg_scale > 1 and negative_prompt is not None`.
    public var usesGuidance: Bool { guidance > 1 && !negativePrompt.isEmpty }
}
