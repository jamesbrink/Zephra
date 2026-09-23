import MLX

/// Whether a decoded picture carries any transparency worth keeping, and the three-channel
/// picture when it does not.
///
/// The autoencoder always decodes four channels, and for an ordinary prompt the fourth is
/// opaque with a little noise on it — measured on the first pictures made here, every alpha
/// landed in 250...255 of 255, with none below. Writing that as an RGBA file would make every
/// picture this model makes read as transparent: the library would draw a checkerboard under
/// a landscape, the inspector would say "Transparent", and a reference well would warn about a
/// matte that changes nothing. So a picture whose alpha never drops below `opaqueFloor` is
/// written opaque, and only a picture with a real hole keeps its alpha, noise included.
enum QwenImage21Opacity {
    /// The lowest alpha, in the decoder's -1...1 range, an opaque picture may carry: 250 of
    /// 255 once scaled to bytes. The noise sits above it; a cut-out's edge is far below it.
    static let opaqueFloor: Float = 250.0 / 255.0 * 2 - 1

    /// `pixels` is `[batch, height, width, 4]` in -1...1. Answers the same array when it has
    /// transparency, and its first three channels when it does not.
    static func flattened(_ pixels: MLXArray) -> MLXArray {
        guard pixels.ndim == 4, pixels.dim(3) == 4 else { return pixels }
        let lowest = pixels[.ellipsis, 3].min().item(Float.self)
        return lowest >= opaqueFloor ? pixels[.ellipsis, ..<3] : pixels
    }
}
