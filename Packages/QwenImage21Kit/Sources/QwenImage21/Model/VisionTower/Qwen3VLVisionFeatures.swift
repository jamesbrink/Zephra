import Foundation
import MLX

/// What the tower answers for one reference picture: the slots that go into the prompt, and the
/// three intermediate views that go into the decoder's first three layers.
///
/// Both are `[slots, 4096]` — the tower projects onto the decoder's own width — and both are
/// needed. The slots replace the `<|image_pad|>` rows of the embedding sequence before layer 0;
/// the DeepStack taps are added at those same rows after layers 0, 1 and 2. A port that
/// returned only the slots would produce a picture that responds to the reference and is not
/// the reference.
public struct Qwen3VLVisionFeatures {
    /// `[slots, outHidden]`: the tower's merged output, one row per image slot.
    public let slots: MLXArray
    /// One `[slots, outHidden]` per `deepstack_visual_indexes` entry, in block order.
    public let deepStack: [MLXArray]

    public init(slots: MLXArray, deepStack: [MLXArray]) {
        self.slots = slots
        self.deepStack = deepStack
    }
}
