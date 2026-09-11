import Foundation

/// One clip to make: what the backend asks the pipeline for.
///
/// Not `Hashable`: a held frame is a `CGImage`, which has no useful equality, and nothing
/// asked a request whether it equalled another one.
public struct LTX2GenerationRequest: Sendable {
    /// What the clip should show.
    public var prompt: String
    /// Pixels across, a multiple of 32.
    public var width: Int
    /// Pixels down, a multiple of 32.
    public var height: Int
    /// Frames, `1 + 8k`.
    public var frames: Int
    /// Frames per second the clip is made at and plays at.
    public var frameRate: Double
    /// The noise seed; the ancestral noise is drawn from `seed + 10000`, as the reference does.
    public var seed: UInt64
    /// How many tokens the prompt is padded or truncated to.
    public var maxPromptTokens: Int
    /// Pictures to hold at the head of the clip — one as its first frame, or the `1 + 8k` last
    /// frames of an earlier clip to carry on from — or nil for ordinary text-to-video.
    public var heldFrames: LTX2HeldFrames?
    /// Whether to make the clip in two stages: the first ladder at half the size, the latent
    /// doubled by the spatial upsampler, and the second, shorter ladder at the full size. The
    /// reference's own route to a large frame; both edges must be multiples of 64.
    public var twoStage: Bool

    public init(
        prompt: String, width: Int, height: Int, frames: Int, frameRate: Double = 24,
        seed: UInt64, maxPromptTokens: Int = LTX2Tokenizer.maxLength,
        heldFrames: LTX2HeldFrames? = nil, twoStage: Bool = false
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.frames = frames
        self.frameRate = frameRate
        self.seed = seed
        self.maxPromptTokens = maxPromptTokens
        self.heldFrames = heldFrames
        self.twoStage = twoStage
    }
}
