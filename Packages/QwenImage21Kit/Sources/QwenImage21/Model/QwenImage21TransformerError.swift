import Foundation

/// What can be wrong with the joint sequence a forward pass is handed, or with its prefix cache.
///
/// Every case is a programming error rather than a bad snapshot: the layout and the cache are
/// built by this package's own pipeline, and each of these is a way to get a plausible picture
/// of the wrong thing instead of a crash.
public enum QwenImage21TransformerError: Error, LocalizedError, Equatable {
    /// The image shapes account for a different number of latent tokens than the slot mask
    /// marks. Blocks are cut by the shapes' token counts, so the two have to agree exactly.
    case imageShapesDoNotMatchSlots(shapeTokens: Int, maskTokens: Int)
    /// A vision-language slot mask with no image slot at all. Even text-to-image appends one
    /// slot per four target latents, so an empty mask means the target was never appended.
    case noImageBlocks
    /// A block's token count is not a multiple of the four latent tokens one slot stands for.
    case blockIsNotWholeSlots(tokens: Int)
    /// A prompt mask of a different length from the text positions it is lifted onto.
    case promptMaskIsTheWrongLength(mask: Int, textPositions: Int)
    /// A cached step ran against a layer whose prefix was never extracted.
    case cacheWasNotExtracted
    /// A cache was handed to a model whose configuration says the prefix is not step-independent.
    case cacheRequiresCausalCondition

    public var errorDescription: String? {
        switch self {
        case .imageShapesDoNotMatchSlots(let shapeTokens, let maskTokens):
            "The image shapes account for \(shapeTokens) latent tokens but the slot mask marks \(maskTokens)."
        case .noImageBlocks:
            "The vision-language slot mask marks no image at all, so there is no target block to make."
        case .blockIsNotWholeSlots(let tokens):
            "A block of \(tokens) latent tokens is not a whole number of the four-token slots the encoder reserved."
        case .promptMaskIsTheWrongLength(let mask, let textPositions):
            "A prompt mask of \(mask) entries cannot be lifted onto \(textPositions) text positions."
        case .cacheWasNotExtracted:
            "A step read a prefix cache that the first step never filled."
        case .cacheRequiresCausalCondition:
            "A prefix cache is only valid where text and condition tokens modulate from t = 0."
        }
    }
}
