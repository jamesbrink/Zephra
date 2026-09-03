import Foundation

/// One image, as the pipeline is asked for it.
///
/// Plain values, so it crosses from the engine's world to the pipeline's without carrying an
/// array along: the reference picture arrives as PNG bytes and is decoded inside the pipeline,
/// where the size it is fitted to is decided.
public struct Flux2GenerationRequest: Hashable, Sendable {
    /// What the image should show, or what to change in the reference.
    public var prompt: String
    /// Rendered width in pixels, a multiple of the size alignment.
    public var width: Int
    /// Rendered height in pixels.
    public var height: Int
    /// Denoising steps. Four is what klein was distilled for.
    public var steps: Int
    /// The noise seed.
    public var seed: UInt64
    /// Positions the prompt is padded or cut to before encoding.
    public var maxPromptTokens: Int
    /// A picture to edit, as PNG bytes, or nil to start from noise.
    public var referenceImage: Data?

    /// Creates a request.
    public init(
        prompt: String,
        width: Int,
        height: Int,
        steps: Int,
        seed: UInt64,
        maxPromptTokens: Int,
        referenceImage: Data? = nil
    ) {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.steps = steps
        self.seed = seed
        self.maxPromptTokens = maxPromptTokens
        self.referenceImage = referenceImage
    }
}
