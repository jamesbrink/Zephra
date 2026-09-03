import CoreGraphics
import Foundation

/// One image to make.
///
/// Not `Hashable` any more: a reference picture is a `CGImage`, which has no useful equality,
/// and nothing asked a request whether it equalled another one.
public struct QwenImageGenerationRequest: Sendable {
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
    /// A picture to start from instead of pure noise, or nil for ordinary text-to-image.
    public var referenceImage: CGImage?
    /// How much of that picture to discard, from 0 (all of it kept) to 1 (none of it).
    ///
    /// At 1 the loop starts at the first sigma, where the mix is pure noise, so a reference at
    /// full strength and no reference at all produce the same image. That is why this defaults
    /// to 1 rather than to something in the middle.
    public var referenceStrength: Double

    public init(
        prompt: String,
        width: Int,
        height: Int,
        steps: Int,
        seed: UInt64,
        maxPromptTokens: Int,
        referenceImage: CGImage? = nil,
        referenceStrength: Double = 1
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
        self.maxPromptTokens = maxPromptTokens
        self.referenceImage = referenceImage
        self.referenceStrength = referenceStrength
    }
}
