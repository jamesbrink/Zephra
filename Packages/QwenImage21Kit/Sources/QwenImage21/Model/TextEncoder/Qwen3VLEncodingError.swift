import Foundation

/// What can go wrong between a prompt string and the hidden states the transformer reads.
///
/// Each case is a disagreement between two counts that must match, and each one is a picture of
/// the wrong prompt if it is let through: an image slot that no tower output fills, or a tower
/// output with no slot to land in, shifts every conditioning vector after it.
public enum Qwen3VLEncodingError: Error, Equatable, Sendable {
    /// The template carries a different number of `<|image_pad|>` tokens than there are
    /// pictures. The template writes exactly one per picture and the expansion makes it a run.
    case imagePadCountDisagrees(pads: Int, pictures: Int)
    /// The tower answered a different number of slots than the prompt made room for.
    case slotCountDisagrees(slots: Int, expected: Int)
    /// A picture's pixel size is not the multiple of `patch_size * merge_size` the tower's own
    /// `smart_resize` would have brought it to. The pipeline fits every reference to a multiple
    /// of 32 before either copy is made, so this is a caller that skipped the fit.
    case sizeNotFitted(height: Int, width: Int, factor: Int)
    /// A picture whose longest edge is more than two hundred times its shortest, which the
    /// reference's `smart_resize` refuses outright rather than resizing.
    case aspectRatioTooExtreme(height: Int, width: Int)
}
