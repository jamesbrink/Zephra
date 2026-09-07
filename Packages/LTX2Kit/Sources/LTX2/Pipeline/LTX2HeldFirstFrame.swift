import Foundation
import MLX

/// A first frame the loop is holding: the picture already encoded and packed, the mask that says
/// which tokens it covers and how strongly, and the strength the transformer is told.
///
/// Made once, before the first step, so the encoder runs once a clip rather than once a step.
struct LTX2HeldFirstFrame {
    /// The picture's latent in the loop's own packed order, `[1, tokens, channels]`, with every
    /// token past the first latent frame zero — the mask is what decides where it is read, so
    /// what is under the rest of it never matters.
    let latent: MLXArray
    /// `[1, tokens, 1]`: the conditioning strength over the first latent frame's tokens.
    let mask: MLXArray
    /// The same strength as a scalar, for the transformer's per-token noise level.
    let strength: Float

    /// Encodes `frame`'s picture at the clip's size and packs it into `layout`'s token order.
    ///
    /// The picture is one pixel frame, which the causal encoder turns into exactly one latent
    /// frame; that frame is padded out to the clip's length with zeros so the arithmetic is one
    /// shape throughout, and the mask keeps the padding out of every use of it.
    init(_ frame: LTX2FirstFrame, layout: LTX2LatentLayout, encoder: LTX2VideoEncoder) throws {
        let pixels = try LTX2FirstFramePixels.pixels(
            from: frame.image,
            width: layout.width * LTX2LatentLayout.scale.width,
            height: layout.height * LTX2LatentLayout.scale.height)
        let encoded = encoder.encode(pixels).asType(.float32)  // [1, channels, 1, h, w]
        let rest = layout.frames - encoded.dim(2)
        let padding = MLXArray.zeros(
            [1, LTX2LatentLayout.channels, rest, layout.height, layout.width])
        latent = layout.pack(rest > 0 ? MLX.concatenated([encoded, padding], axis: 2) : encoded)
        mask = LTX2FirstFrameConditioning.mask(layout: layout, strength: frame.strength)
        strength = frame.strength
    }
}
