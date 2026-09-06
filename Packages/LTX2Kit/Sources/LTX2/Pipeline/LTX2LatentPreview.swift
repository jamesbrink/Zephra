import Foundation
import MLX
import ZephraMLX

/// A small picture of a clip still being made: its first frame, decoded from a pooled copy of
/// the run's estimate of the finished latent.
///
/// The first latent frame only, because it is the one frame the decoder can make on its own:
/// each temporal doubling drops its leading frame, so `F' = 1` decodes to exactly one pixel
/// frame, and every further latent frame would cost eight more decoded ones nobody looks at.
/// Pooled to `cellLimit` cells on the long edge, because a cell here is 32 pixels rather than
/// the 8 of every other family: `LatentPreview`'s 32-cell limit would decode a 1024-pixel
/// preview of a 768-pixel clip, and a preview frame is capped at 256 pixels an edge.
/// `LatentPreview.pooled` does the pooling; the decode is the family's own decoder, whole, on
/// a tensor of at most 8 x 8 x 1 cells, which is why a frame costs milliseconds.
public struct LTX2LatentPreview: Sendable {
    /// Latent cells the long edge is pooled down to: 8 cells of 32 pixels, 256 pixels.
    public static let cellLimit = 8

    public let width: Int
    public let height: Int
    /// RGBA8, row-major, opaque.
    public let pixels: Data

    /// Decodes the first frame of `latent`, `[1, channels, frames, height, width]` in the
    /// loop's normalised space, through `decoder`.
    public static func make(latent: MLXArray, decoder: LTX2VideoDecoder) -> LTX2LatentPreview {
        let first = latent[0..., 0..., 0]  // [1, channels, height, width]
        let pooled = LatentPreview.pooled(first, by: poolingFactor(height: first.dim(2), width: first.dim(3)))
        let video = decoder.decode(pooled.expandedDimensions(axis: 2))  // [1, 1, h, w, 3]
        let frame = video[0..., 0].asType(.float32)  // [1, h, w, 3]
        return LTX2LatentPreview(
            width: frame.dim(2), height: frame.dim(1), pixels: LatentPreview.rgba8(frame))
    }

    /// How much to pool a latent of this size by, so its long edge comes in under `cellLimit`;
    /// never less than 1.
    static func poolingFactor(height: Int, width: Int) -> Int {
        let longest = Swift.max(height, width)
        guard longest > cellLimit else { return 1 }
        return (longest + cellLimit - 1) / cellLimit
    }
}
