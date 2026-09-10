import Foundation
import MLX

/// The shape of a clip's latent and the token sequence the transformer reads it as.
///
/// The video autoencoder compresses four frames and 16 pixels per side into one cell, keeping
/// the first frame on its own, so a clip of `4k + 1` frames is `k + 1` latent frames; the
/// transformer then patches two cells by two into one token, so a token stands for 32 pixels
/// a side and the sequence is every patch in frame-major, row, column order. The latent is
/// `[1, 48, frames, height, width]`, channels first, as diffusers holds it.
public struct WanLatentLayout: Hashable, Sendable {
    /// Latent channels per cell.
    public static let channels = 48
    /// Pixel frames one latent frame covers after the first.
    public static let frameScale = 4
    /// Pixels a latent cell covers on each side.
    public static let cellScale = 16
    /// Cells a transformer token covers on each side.
    public static let patch = 2
    /// Pixels a token covers on each side: what a request's size must be a multiple of.
    public static let pixelAlignment = cellScale * patch

    /// Latent frames.
    public let frames: Int
    /// Latent rows.
    public let height: Int
    /// Latent columns.
    public let width: Int

    /// The layout for a clip of `frames` pixel frames at `width` by `height` pixels. The frame
    /// count is expected on the `4k + 1` ladder and the size in multiples of 32; the caller's
    /// capabilities clamp both before a request is made.
    public init(pixelFrames: Int, pixelWidth: Int, pixelHeight: Int) {
        frames = (pixelFrames - 1) / Self.frameScale + 1
        height = pixelHeight / Self.cellScale
        width = pixelWidth / Self.cellScale
    }

    /// The layout of a latent already in hand.
    public init(frames: Int, height: Int, width: Int) {
        self.frames = frames
        self.height = height
        self.width = width
    }

    /// Tokens the transformer reads: one per patch.
    public var tokens: Int { frames * (height / Self.patch) * (width / Self.patch) }
    /// Tokens in the first latent frame, the ones a held picture occupies.
    public var firstFrameTokens: Int { (height / Self.patch) * (width / Self.patch) }
    /// Pixel frames the decoder will make: `4 * (frames - 1) + 1`.
    public var pixelFrames: Int { Self.frameScale * (frames - 1) + 1 }
    /// The latent's shape, `[1, channels, frames, height, width]`.
    public var latentShape: [Int] { [1, Self.channels, frames, height, width] }
}
