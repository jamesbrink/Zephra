import Foundation

/// One image's latent grid, in the order the transformer reads them: every condition image
/// first and the target image last.
///
/// The frame count is the reference's, and 2.1 is a still-image model, so it is one. It is kept
/// rather than dropped because the reference counts a block's tokens with it and counts a
/// block's *positions* without it, and those are two different arithmetics that happen to agree
/// at one frame; a port that collapsed them would be right only by luck.
public struct QwenImage21ImageShape: Hashable, Sendable {
    /// Latent frames. One, for every entry 2.1 ships.
    public let frames: Int
    /// Latent rows.
    public let height: Int
    /// Latent columns.
    public let width: Int

    /// How many latent tokens this image occupies in the joint sequence.
    public var tokenCount: Int { frames * height * width }

    /// How far the shared frame counter advances past this block: the longer edge, never the
    /// token count. A block's own rows and columns are centred on zero, so the frame axis is
    /// the only thing that says where in the sequence it sat.
    public var frameAdvance: Int { max(height, width) }

    /// One grid, in latent cells.
    public init(frames: Int = 1, height: Int, width: Int) {
        self.frames = frames
        self.height = height
        self.width = width
    }
}
