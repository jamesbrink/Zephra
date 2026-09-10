import Foundation

/// One clip to make: what the backend asks the pipeline for.
///
/// Not `Hashable`: a held first frame is a `CGImage`, which has no useful equality, and nothing
/// asked a request whether it equalled another one.
public struct WanGenerationRequest: Sendable {
    /// The text the clip is made from.
    public var prompt: String
    /// Pixels across, a multiple of 32: the autoencoder's 16 times the transformer's patch of 2.
    public var width: Int
    /// Pixels down, a multiple of 32.
    public var height: Int
    /// Frames, `1 + 4k`: the autoencoder keeps the first frame and packs four into each latent
    /// frame after it.
    public var frames: Int
    /// Frames per second the clip plays at.
    public var frameRate: Double
    /// The seed for the starting noise and for the re-draw between steps.
    public var seed: UInt64
    /// A picture to hold as the first frame, or nil for text to video.
    public var firstFrame: WanFirstFrame?
    /// The decoder's tile edge in latent cells, or nil for the exact, untiled decode.
    public var vaeTile: Int?

    public init(
        prompt: String, width: Int, height: Int, frames: Int, frameRate: Double = WanKit.frameRate,
        seed: UInt64, firstFrame: WanFirstFrame? = nil, vaeTile: Int? = nil
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.frames = frames
        self.frameRate = frameRate
        self.seed = seed
        self.firstFrame = firstFrame
        self.vaeTile = vaeTile
    }
}
