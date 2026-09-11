import Foundation

/// The shape of a clip's audio latent and the token sequence the transformer reads it as:
/// one token per latent frame, 128 wide, at twenty-five frames a second of the clip.
public struct LTX2AudioLatentLayout: Hashable, Sendable {
    /// The packed width of one token: every channel of every latent mel bin.
    public static let channels = 128

    /// Latent audio frames.
    public let frames: Int

    /// The layout for a clip of `pixelFrames` frames at `frameRate`, as the reference rounds
    /// it: 49 frames at 24 a second are 51 audio frames.
    public init(pixelFrames: Int, frameRate: Double, latentsPerSecond: Double = 25) {
        frames = Int((Double(pixelFrames) / frameRate * latentsPerSecond).rounded())
    }

    /// The layout of a latent already in hand.
    public init(frames: Int) {
        self.frames = frames
    }

    /// The tokens' shape, `[1, frames, channels]`.
    public var shape: [Int] { [1, frames, Self.channels] }
}
