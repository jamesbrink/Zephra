import Foundation
import MLX

/// Turns a latent image into the token sequence the transformer reads, and back.
///
/// **There is no patchify.** `patch_size` is 1, so `_pack_latents` in the reference is a plain
/// spatial flatten: one transformer token is one latent cell, which is one 16-by-16 tile of the
/// picture. A 1024-square image is 64 by 64 cells and therefore 4096 tokens. The `4` that turns
/// up elsewhere in the model is not a patch, it is how many latent tokens one vision-language
/// image slot stands for, and it lives with the joint sequence rather than here.
///
/// Both moves are one reshape and one transpose, and getting the axis order wrong scrambles the
/// picture into plausible-looking noise rather than failing.
public enum QwenImage21LatentPacking {
    /// Latent cells along each edge of a token. One, and stated so the arithmetic below names
    /// what it assumes.
    public static let patchSize = 1

    /// `[batch, channels, height, width]` to `[batch, height * width, channels]`, row-major.
    public static func tokens(_ latents: MLXArray) -> MLXArray {
        let shape = latents.shape
        let (batch, channels, height, width) = (shape[0], shape[1], shape[2], shape[3])
        return latents.reshaped([batch, channels, height * width]).transposed(0, 2, 1)
    }

    /// `[batch, height * width, channels]` back to `[batch, channels, height, width]`.
    public static func grid(_ tokens: MLXArray, height: Int, width: Int) -> MLXArray {
        let batch = tokens.shape[0]
        let channels = tokens.shape[2]
        return tokens.transposed(0, 2, 1).reshaped([batch, channels, height, width])
    }

    /// How many tokens a latent grid of this size becomes. The schedule's shift is a function
    /// of this, so it is worth having a name.
    public static func tokenCount(latentHeight: Int, latentWidth: Int) -> Int {
        latentHeight * latentWidth
    }

    /// One entry of the transformer's `img_shapes`: a latent grid, with the frame axis the
    /// image specialisation always leaves at one.
    public struct Shape: Hashable, Sendable {
        /// Frames. Always one for a picture.
        public let frames: Int
        /// Latent rows.
        public let height: Int
        /// Latent columns.
        public let width: Int

        public init(frames: Int = 1, height: Int, width: Int) {
            self.frames = frames
            self.height = height
            self.width = width
        }

        /// Tokens this grid occupies in the joint sequence.
        public var tokenCount: Int { frames * height * width }
    }

    /// `img_shapes` for one sample: every condition image's grid in order, then the target's.
    ///
    /// The order is the reference's and is load-bearing twice over — the condition latents are
    /// prepended to the noise on every step and the prediction is sliced to the tail, and the
    /// rotary walks the same list to lay the frame axis out.
    public static func shapes(
        conditions: [(latentHeight: Int, latentWidth: Int)],
        target: (latentHeight: Int, latentWidth: Int)
    ) -> [Shape] {
        conditions.map { Shape(height: $0.latentHeight, width: $0.latentWidth) }
            + [Shape(height: target.latentHeight, width: target.latentWidth)]
    }
}
