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

    public init(prompt: String, width: Int, height: Int, steps: Int, seed: UInt64) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
    }
}
