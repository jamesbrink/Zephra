import Foundation
import MLX

/// Turning the latent of a generation still in flight into a small picture of it.
///
/// A frame is the family's own autoencoder run over a pooled copy of the latent: pooling the
/// long edge down to `cellLimit` makes the decode about a sixteenth of the real one at 1024
/// pixels, which is what keeps a frame every three quarters of a second from being felt. It is
/// the family's own decoder rather than a fitted latent-to-RGB matrix because the published
/// matrices are in GPL code and cannot be copied; see ROADMAP.
///
/// Nothing here knows which autoencoder it is in front of. The two halves that are the same for
/// every family live here — how far to pool, and how to turn the decoded pixels into bytes a
/// host can draw — and each kit's `<Family>LatentPreview` supplies the denormalisation and the
/// decode in between. The vendored `ZImageKit` keeps its own copy of both halves, as it does of
/// the tiled decode, so that re-syncing it never has to reason about our packages.
public nonisolated enum LatentPreview {
    /// The longest edge, in latent cells, a preview is pooled down to. Eight pixels a cell in
    /// every autoencoder the app ships, so a frame is at most 256 pixels on its long edge.
    public static let cellLimit = 32

    /// How much to pool a latent of this size by, so its long edge comes in under `cellLimit`.
    /// Never less than 1: a latent already small enough is decoded as it is.
    public static func poolingFactor(height: Int, width: Int) -> Int {
        let longest = Swift.max(height, width)
        guard longest > cellLimit else { return 1 }
        return (longest + cellLimit - 1) / cellLimit
    }

    /// Average-pools an NCHW latent by `factor` on both spatial axes.
    ///
    /// Cells past the last whole block are dropped rather than partly averaged, which loses at
    /// most three cells an edge from a frame that is already a thumbnail. Averaging rather than
    /// sampling because a latent is not smooth: taking every fourth cell of one aliases into
    /// visible speckle, where the mean of each block does not.
    public static func pooled(_ latents: MLXArray, by factor: Int) -> MLXArray {
        guard factor > 1 else { return latents }
        let (batch, channels) = (latents.dim(0), latents.dim(1))
        let height = (latents.dim(2) / factor) * factor
        let width = (latents.dim(3) / factor) * factor
        guard height > 0, width > 0 else { return latents }
        return MLX.mean(
            latents[0..., 0..., 0..<height, 0..<width]
                .reshaped([batch, channels, height / factor, factor, width / factor, factor]),
            axes: [3, 5])
    }

    /// One decoded frame as RGBA8 bytes, row-major, straight alpha: `PixelBuffer.rgba8`, the
    /// same packing the finished image gets, rounding included.
    ///
    /// - Parameter image: `[1, height, width, 3 or 4]` in the range -1 to 1, which is what
    ///   every autoencoder in the app decodes to. A frame the packer has no layout for throws,
    ///   and a dropped frame is a glimpse nobody sees rather than a run that fails.
    public static func rgba8(_ image: MLXArray) throws -> Data {
        try PixelBuffer.rgba8(image)
    }
}
