import Foundation

/// One image to make.
public struct QwenImageGenerationRequest: Hashable, Sendable {
    /// What the image should show.
    public var prompt: String
    /// Pixels across.
    public var width: Int
    /// Pixels down.
    public var height: Int
    /// Denoising steps.
    public var steps: Int
    /// The noise seed, so an image can be reproduced exactly.
    public var seed: UInt64
    /// How many of the prompt's own tokens condition the image; the rest are dropped.
    public var maxPromptTokens: Int

    public init(
        prompt: String, width: Int, height: Int, steps: Int, seed: UInt64, maxPromptTokens: Int
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
        self.maxPromptTokens = maxPromptTokens
    }
}
