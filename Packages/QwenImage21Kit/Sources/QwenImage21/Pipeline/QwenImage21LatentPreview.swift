import Foundation
import MLX
import ZephraMLX

/// One frame of a 2.1 generation still in flight: the run's estimate of the finished latent,
/// pooled and decoded small.
///
/// The pooling arithmetic is `LatentPreview`'s, but **not its limit**. `LatentPreview.cellLimit`
/// is 32 cells because every other family's cell is eight pixels, which makes a 256-pixel
/// frame — the size `GenerationPreview` is drawn at. This autoencoder's cell is sixteen, so the
/// shared limit made 512-pixel frames: four times the pixels anybody sees, through a float32
/// decoder, which measured 2.3 seconds a frame at 1024 square. `cellLimit` here is 16, the same
/// 256 pixels. The decode is untiled, since a frame that small has no peak worth bounding.
///
/// The bytes are `ZephraMLX.PixelBuffer`'s, which carries a fourth channel as the picture's own
/// straight alpha rather than appending an opaque one. `LatentPreview.rgba8` is the
/// three-channel door and would make five channels out of these four, so it is deliberately not
/// what a 2.1 frame goes through.
public struct QwenImage21LatentPreview: Sendable {
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// `width * height * 4` bytes, RGBA8, row-major, the fourth the picture's own alpha.
    public let pixels: Data

    /// The longest edge, in this autoencoder's sixteen-pixel cells, a frame is pooled down to:
    /// 256 pixels, the edge every other family's frame has.
    public static let cellLimit = 16

    /// How much to pool a latent of this size by, so its long edge comes in at `cellLimit` or
    /// under. One for a latent already that small.
    public static func poolingFactor(height: Int, width: Int) -> Int {
        let longest = max(height, width)
        guard longest > cellLimit else { return 1 }
        return (longest + cellLimit - 1) / cellLimit
    }

    /// Decodes one estimate of the finished latent.
    ///
    /// - Parameters:
    ///   - latents: `[1, height, width, zDim]` in the **transformer's** space -- the loop's
    ///     estimate of the finished latent, `x - sigma * v`, never the latent it holds, which
    ///     decodes to mush on a bent schedule.
    ///   - normalization: the statistics that put it back in the autoencoder's space.
    ///   - autoencoder: the loaded model's, which is the only decoder that means anything here.
    public static func make(
        latents: MLXArray,
        normalization: QwenImage21LatentNormalization,
        autoencoder: QwenImage21Autoencoder
    ) throws -> QwenImage21LatentPreview {
        let factor = poolingFactor(height: latents.dim(1), width: latents.dim(2))
        // `LatentPreview.pooled` takes a channels-first latent, as the other families hold one;
        // 2.1's crosses channels last, so it is turned for the pooling and turned back. Two
        // transposes of a thumbnail, against one more copy of the pooling arithmetic.
        let pooled = LatentPreview.pooled(latents.transposed(0, 3, 1, 2), by: factor)
            .transposed(0, 2, 3, 1)
        let image = autoencoder.decodeUntiled(normalization.denormalize(pooled))
        eval(image)
        return QwenImage21LatentPreview(
            width: image.dim(2), height: image.dim(1),
            pixels: try PixelBuffer.rgba8(image))
    }
}
