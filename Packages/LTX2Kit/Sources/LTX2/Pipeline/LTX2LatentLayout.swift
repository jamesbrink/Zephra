import Foundation
import MLX

/// The shape of a clip's latent and the token sequence the transformer reads it as.
///
/// The video autoencoder compresses eight frames and 32 pixels per side into one cell, keeping
/// the first frame on its own, so a clip of `8k + 1` frames is `k + 1` latent frames; the
/// transformer's patch is one cell (`patch_size 1`), so the sequence is every cell in
/// frame-major, row, column order with its 128 channels as the token. `LTX2VideoPositions`
/// orders its positions the same way, which is the whole contract between the two.
public struct LTX2LatentLayout: Hashable, Sendable {
    /// Latent channels per cell.
    public static let channels = 128
    /// Pixel frames, rows and columns one cell covers.
    public static let scale = LTX2VideoPositions.latentScale

    /// Latent frames.
    public let frames: Int
    /// Latent rows.
    public let height: Int
    /// Latent columns.
    public let width: Int

    /// The layout for a clip of `frames` pixel frames at `width` by `height` pixels. The frame
    /// count is expected on the `8k + 1` ladder and the size in multiples of 32; the caller's
    /// capabilities clamp both before a request is made.
    public init(pixelFrames: Int, pixelWidth: Int, pixelHeight: Int) {
        frames = (pixelFrames - 1) / Self.scale.frames + 1
        height = pixelHeight / Self.scale.height
        width = pixelWidth / Self.scale.width
    }

    /// The layout of a latent already in hand.
    public init(frames: Int, height: Int, width: Int) {
        self.frames = frames
        self.height = height
        self.width = width
    }

    /// Cells, which is tokens.
    public var tokens: Int { frames * height * width }
    /// Pixel frames the decoder will make: `8 * (frames - 1) + 1`.
    public var pixelFrames: Int { Self.scale.frames * (frames - 1) + 1 }
    /// The latent's shape, `[1, channels, frames, height, width]`.
    public var latentShape: [Int] { [1, Self.channels, frames, height, width] }

    /// `[batch, channels, frames, height, width]` into `[batch, tokens, channels]`.
    public func pack(_ latent: MLXArray) -> MLXArray {
        latent.reshaped([latent.shape[0], latent.shape[1], -1]).transposed(0, 2, 1)
    }

    /// `[batch, tokens, channels]` back into `[batch, channels, frames, height, width]`.
    public func unpack(_ tokens: MLXArray) -> MLXArray {
        tokens.transposed(0, 2, 1).reshaped([tokens.shape[0], tokens.shape[2], frames, height, width])
    }

    /// Rotary positions for every token, in this order, for a clip at `frameRate`.
    public func positions(frameRate: Double) -> MLXArray {
        LTX2VideoPositions.midpoints(frames: frames, height: height, width: width, frameRate: frameRate)
    }

    /// Tokens of the first latent frame: the ones that encode a single pixel frame, which the
    /// transformer marks with its keyframe embedding.
    public var firstFrameTokens: Int { height * width }

    /// Tokens of the first `frames` latent frames, which is what a held run of frames covers.
    public func frameTokens(_ frames: Int) -> Int { frames * height * width }
}
