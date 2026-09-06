import Foundation

/// One clip to make: what the backend asks the pipeline for.
public struct LTX2GenerationRequest: Hashable, Sendable {
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

    public init(
        prompt: String, width: Int, height: Int, frames: Int, frameRate: Double = 24,
        seed: UInt64, maxPromptTokens: Int = LTX2Tokenizer.maxLength
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.frames = frames
        self.frameRate = frameRate
        self.seed = seed
        self.maxPromptTokens = maxPromptTokens
    }
}
