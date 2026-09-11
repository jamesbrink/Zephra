import Foundation
import MLX

/// The frames the loop is holding: the pictures already encoded and packed, the mask that says
/// which tokens they cover and how strongly, and the strength the transformer is told.
///
/// Made once, before the first step, so the encoder runs once a clip rather than once a step.
struct LTX2HeldLatent {
    /// The pictures' latent in the loop's own packed order, `[1, tokens, channels]`, with every
    /// token past the held latent frames zero — the mask is what decides where it is read, so
    /// what is under the rest of it never matters.
    let latent: MLXArray
    /// `[1, tokens, 1]`: the conditioning strength over the held latent frames' tokens.
    let mask: MLXArray
    /// The same strength as a scalar, for the transformer's per-token noise level.
    let strength: Float
    /// How many latent frames are held, from the head: one for a single picture, `k + 1` for
    /// a run of `1 + 8k`.
    let latentFrames: Int

    /// Encodes `frames`' pictures at the clip's size and packs them into `layout`'s token order.
    ///
    /// The pictures are `1 + 8k` pixel frames, which the causal encoder turns into exactly
    /// `k + 1` latent frames, the first standing on its own; they are padded out to the clip's
    /// length with zeros so the arithmetic is one shape throughout, and the mask keeps the
    /// padding out of every use of it.
    init(_ frames: LTX2HeldFrames, layout: LTX2LatentLayout, encoder: LTX2VideoEncoder) throws {
        let pixels = try LTX2FirstFramePixels.pixels(
            from: frames.images,
            width: layout.width * LTX2LatentLayout.scale.width,
            height: layout.height * LTX2LatentLayout.scale.height)
        let encoded = encoder.encode(pixels).asType(.float32)  // [1, channels, k + 1, h, w]
        latentFrames = encoded.dim(2)
        let rest = layout.frames - latentFrames
        let padding = MLXArray.zeros(
            [1, LTX2LatentLayout.channels, rest, layout.height, layout.width])
        latent = layout.pack(rest > 0 ? MLX.concatenated([encoded, padding], axis: 2) : encoded)
        mask = LTX2FirstFrameConditioning.mask(layout: layout, strength: frames.strength, frames: latentFrames)
        strength = frames.strength
    }
}
