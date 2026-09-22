import Foundation
import MLX

/// DeepStack: the tower's intermediate views of a reference picture, added into the decoder's
/// own stream at the picture's token slots.
///
/// The tower taps the outputs of blocks 8, 16 and 24 (`deepstack_visual_indexes`), runs each
/// through its own post-shuffle merger, and hands back three `[slots, hidden]` tensors. Entry
/// `i` is added into the hidden state **after decoder layer `i`**, for `i` in 0, 1, 2 — the
/// reference's `layer_idx in range(len(deepstack_visual_embeds))` in `Qwen3VLTextModel.forward`,
/// which is a list index and not a configured depth. None of this runs for a text-only prompt,
/// and dropping it entirely still produces a plausible picture of the wrong reference, which is
/// why the injection layers are pinned by `DeepStackTests` rather than read off the config.
///
/// The additions are built once, as dense `[1, tokens, hidden]` tensors that are zero outside
/// the slots, so the decoder's loop is one add and holds no index arithmetic. A picture's slots
/// are one contiguous run — the processor expands a single `<|image_pad|>` into its whole run —
/// so the dense form is slicing and concatenation only, and it stays correct for several
/// pictures, whose runs are laid out in the order the tower's slots are.
public struct Qwen3VLDeepStack {
    /// One `[1, tokens, hidden]` addition per tap, in tap order.
    public let additions: [MLXArray]

    /// How many decoder layers take an injection: the first `additions.count`.
    public var layerCount: Int { additions.count }

    /// Spreads each tap over a sequence `tokens` long, zero everywhere but the image runs.
    ///
    /// - Parameters:
    ///   - taps: The tower's merger outputs, each `[slots, hidden]`, slots summed over pictures.
    ///   - runs: Each picture's token slots, in the order the pictures were encoded.
    ///   - tokens: The whole prompt's length.
    public init(taps: [MLXArray], runs: [Range<Int>], tokens: Int) {
        additions = taps.map { Self.spread($0, over: runs, tokens: tokens) }
    }

    /// The hidden state with tap `index` added, or unchanged where there is no such tap.
    public func injected(_ hidden: MLXArray, after index: Int) -> MLXArray {
        guard index < additions.count else { return hidden }
        return hidden + additions[index].asType(hidden.dtype)
    }

    private static func spread(_ tap: MLXArray, over runs: [Range<Int>], tokens: Int) -> MLXArray
    {
        Qwen3VLSlotWriting.spread(tap, runs: runs, tokens: tokens)
    }
}
