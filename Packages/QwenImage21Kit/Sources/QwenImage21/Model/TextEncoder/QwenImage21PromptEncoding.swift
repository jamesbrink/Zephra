import Foundation
import MLX

/// What one prompt becomes: the conditioning the transformer reads, and the two facts about it
/// the joint sequence needs.
///
/// The embeddings begin at the user turn's `<|im_start|>` — the system turn's `dropIndex`
/// states are thrown away — and they are the output of decoder layer 35 **before** the stack's
/// final norm. There is no padding here: one prompt is encoded at a time, and right-padding a
/// batch to a common length is the caller's, since only the caller knows what it is batching
/// against.
public struct QwenImage21PromptEncoding {
    /// `[1, length, hidden]`: the conditioning, in the encoder's own dtype.
    public let embeddings: MLXArray
    /// Tokens kept after the drop.
    public let length: Int
    /// Which of those tokens are a reference picture's slots: `[1, length]`, one where they are.
    ///
    /// The transformer reads this to lay the joint sequence out — each slot stands for four
    /// latent cells — so it is dropped by the same `dropIndex` the states are, and a mask one
    /// token out puts a reference's tokens beside the wrong latents.
    public let imagePadMask: MLXArray
    /// Each picture's slots inside `length`, in the order the pictures were given.
    public let imageRuns: [Range<Int>]

    public init(
        embeddings: MLXArray, length: Int, imagePadMask: MLXArray, imageRuns: [Range<Int>]
    ) {
        self.embeddings = embeddings
        self.length = length
        self.imagePadMask = imagePadMask
        self.imageRuns = imageRuns
    }
}
