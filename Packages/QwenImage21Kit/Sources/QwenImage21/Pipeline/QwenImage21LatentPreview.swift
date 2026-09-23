import Foundation
import MLX
import ZephraMLX

/// One frame of a 2.1 generation still in flight: the run's estimate of the finished latent,
/// decoded at the run's own size and shrunk **after** the decode.
///
/// The pooling arithmetic is `LatentPreview`'s, but its limit is not, and neither is where the
/// pooling happens. Every other family pools the latent before decoding it, which on an
/// eight-pixel, sixteen-channel cell is a blur of the picture. This autoencoder's cell is
/// sixteen pixels of a sixty-four-channel code, and a mean over a block of those codes decodes
/// to a smear rather than a blur: a 1024 run pooled four to one showed the composition by step
/// five and then nothing more, because everything forty steps go on adding lives at the
/// frequencies the pooling had already thrown away. So the latent is decoded whole up to
/// `cellLimit` cells an edge, 1024 pixels, and the *pixels* are pooled to at most `pixelLimit`
/// an edge; only a latent past that limit, the 2K presets, is pooled before the decode, and
/// never by more than it has to be. Measured on halcyon, 0.96 s a frame at 1024 against 0.09 s
/// for the sixteen-cell decode it replaces, which is about a tenth of a step.
///
/// The decode runs in the run's own tile. A frame is the same pass the finished picture takes,
/// and a 16 GB Mac that streams this model tiles that pass to stay inside its budget; an
/// untiled decode at every step would be the peak the tile exists to avoid, forty times over.
///
/// The bytes are `ZephraMLX.PixelBuffer`'s, which carries a fourth channel as the picture's own
/// straight alpha rather than appending an opaque one. `LatentPreview.rgba8` is the
/// three-channel door and would make five channels out of these four, so it is deliberately not
/// what a 2.1 frame goes through. The frame is flattened first by `QwenImage21Opacity`, the rule
/// the finished picture follows: an opaque run's alpha lands at 250...255, and carried as it came
/// every frame of it would read as transparent and be drawn over a checkerboard, here and in the
/// JPEG a phone is sent. A frame with a real hole keeps its alpha.
public struct QwenImage21LatentPreview: Sendable {
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// `width * height * 4` bytes, RGBA8, row-major, the fourth the picture's own alpha.
    public let pixels: Data

    /// The longest edge, in this autoencoder's sixteen-pixel cells, a latent is decoded whole
    /// at: 1024 pixels, the default size. Past it the latent is pooled before the decode.
    public static let cellLimit = 64

    /// The longest edge, in pixels, a frame is shrunk to after the decode.
    public static let pixelLimit = 512

    /// How much to pool a latent of this size by, so its long edge comes in at `cellLimit` or
    /// under. One for a latent already that small.
    public static func poolingFactor(height: Int, width: Int) -> Int {
        factor(fitting: max(height, width), under: cellLimit)
    }

    /// How much to pool a decoded picture of this size by, so its long edge comes in at
    /// `pixelLimit` or under. One for a picture already that small.
    public static func pixelPoolingFactor(height: Int, width: Int) -> Int {
        factor(fitting: max(height, width), under: pixelLimit)
    }

    private static func factor(fitting longest: Int, under limit: Int) -> Int {
        guard longest > limit else { return 1 }
        return (longest + limit - 1) / limit
    }

    /// Decodes one estimate of the finished latent.
    ///
    /// - Parameters:
    ///   - latents: `[1, height, width, zDim]` in the **transformer's** space -- the loop's
    ///     estimate of the finished latent, `x - sigma * v`, never the latent it holds, which
    ///     decodes to mush on a bent schedule.
    ///   - normalization: the statistics that put it back in the autoencoder's space.
    ///   - autoencoder: the loaded model's, which is the only decoder that means anything here.
    ///   - tile: the run's decode tile in latent cells, or nil for one pass; what the finished
    ///     picture's decode is handed, so a frame never peaks higher than the picture will.
    public static func make(
        latents: MLXArray,
        normalization: QwenImage21LatentNormalization,
        autoencoder: QwenImage21Autoencoder,
        tile: Int? = nil
    ) throws -> QwenImage21LatentPreview {
        // `LatentPreview.pooled` takes a channels-first array, as the other families hold a
        // latent; 2.1's latent and its picture both cross channels last, so each is turned for
        // the pooling and turned back. Four transposes of a frame, against one more copy of
        // the pooling arithmetic.
        let pooled = pool(latents, by: poolingFactor(height: latents.dim(1), width: latents.dim(2)))
        let image = autoencoder.decode(normalization.denormalize(pooled), tile: tile)
        let shrunk = pool(image, by: pixelPoolingFactor(height: image.dim(1), width: image.dim(2)))
        eval(shrunk)
        return try frame(shrunk)
    }

    /// A channels-last array mean-pooled over its two middle axes.
    private static func pool(_ array: MLXArray, by factor: Int) -> MLXArray {
        guard factor > 1 else { return array }
        return LatentPreview.pooled(array.transposed(0, 3, 1, 2), by: factor).transposed(0, 2, 3, 1)
    }

    /// Packs a decoded `[1, height, width, 4]` picture in -1...1 as a frame: flattened to three
    /// channels, and so an opaque alpha column, when its alpha never drops below the opaque floor.
    static func frame(_ image: MLXArray) throws -> QwenImage21LatentPreview {
        QwenImage21LatentPreview(
            width: image.dim(2), height: image.dim(1),
            pixels: try PixelBuffer.rgba8(QwenImage21Opacity.flattened(image)))
    }
}
