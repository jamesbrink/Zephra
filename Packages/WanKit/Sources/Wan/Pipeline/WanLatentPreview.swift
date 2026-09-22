import Foundation
import MLX
import ZephraMLX

/// A small picture of a clip still being made: one frame of it, decoded from a pooled copy of
/// the run's estimate of the finished latent.
///
/// One latent frame only, because it is the one frame the decoder can make on its own: the
/// autoencoder keeps the first frame alone and packs four into every latent frame after it, so
/// a single latent frame decodes to exactly one pixel frame. Pooled to `cellLimit` cells on the
/// long edge, because a cell here is 16 pixels: sixteen cells are the 256 pixels a preview
/// frame is capped at. `LatentPreview.pooled` does the pooling; the decode is the family's own
/// decoder, whole, on a tensor of at most 16 x 16 x 1 cells.
public struct WanLatentPreview: Sendable {
    /// Latent cells the long edge is pooled down to: 16 cells of 16 pixels, 256 pixels.
    public static let cellLimit = 16

    public let width: Int
    public let height: Int
    /// RGBA8, row-major, straight alpha; 255 everywhere for a model that makes no
    /// transparency, which every video model is.
    public let pixels: Data

    /// Decodes one frame of `latent`, `[1, channels, frames, height, width]` in the loop's
    /// normalised space, through `decoder`.
    ///
    /// `frame` is 0 for an ordinary run. A run holding a picture as its first frame asks for
    /// the next one instead: frame 0 there is the picture that was handed in, unchanged at
    /// every step, and would say nothing about how the clip is coming along.
    static func make(
        latent: MLXArray, decoder: WanVideoAutoencoder, normalization: WanLatentNormalization,
        frame: Int = 0
    ) throws -> WanLatentPreview {
        let one = latent[0..., 0..., frame..<(frame + 1)]  // [1, channels, 1, height, width]
        let pooled = LatentPreview.pooled(
            one[0..., 0..., 0], by: poolingFactor(height: one.dim(3), width: one.dim(4)))
        let video = decoder.decode(
            normalization.denormalize(pooled.expandedDimensions(axis: 2)).asType(decoder.dtype))
        let picture = video[0..., 0].asType(.float32)  // [1, h, w, 3]
        return WanLatentPreview(
            width: picture.dim(2), height: picture.dim(1),
            pixels: try LatentPreview.rgba8(picture))
    }

    /// How much to pool a latent of this size by, so its long edge comes in under `cellLimit`;
    /// never less than 1.
    static func poolingFactor(height: Int, width: Int) -> Int {
        let longest = Swift.max(height, width)
        guard longest > cellLimit else { return 1 }
        return (longest + cellLimit - 1) / cellLimit
    }
}
