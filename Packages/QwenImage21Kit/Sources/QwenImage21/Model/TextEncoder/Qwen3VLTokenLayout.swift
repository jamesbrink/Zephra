import Foundation

/// A tokenised prompt with each picture's `<|image_pad|>` grown into the run of slots the tower
/// will fill, and those runs remembered.
///
/// `QwenImage21PromptTemplate` writes **one** `<|image_pad|>` per picture, because how many
/// slots a picture is worth is something only its patch grid knows: `t * h * w / merge²`, which
/// is `(height / 32) * (width / 32)` at the published numbers. The processor does this
/// expansion inside `self.processor(text=..., images=...)`; here it is a step of its own, so
/// the runs are available afterwards for three things that each need them — the three-axis
/// positions, the scatter of the tower's slots into the embedding sequence, and DeepStack.
///
/// The runs are contiguous and in picture order, which is what lets every one of those three be
/// slicing rather than scatter.
public struct Qwen3VLTokenLayout: Hashable, Sendable {
    /// The token ids, pads expanded.
    public let ids: [Int]
    /// Each picture's slots, in the order the pictures were given.
    public let imageRuns: [Range<Int>]

    /// Tokens in the prompt.
    public var count: Int { ids.count }

    /// Slots across every picture.
    public var slotCount: Int { imageRuns.reduce(0) { $0 + $1.count } }

    /// A layout for a prompt with no pictures.
    public init(ids: [Int]) {
        self.ids = ids
        imageRuns = []
    }

    /// Grows each `imageTokenID` in `ids` into `grids[i].slotCount(mergeSize:)` copies.
    ///
    /// - Throws: `Qwen3VLEncodingError.imagePadCountDisagrees` when the template's pad count is
    ///   not the number of pictures, which means the template and the picture list came from
    ///   two different places.
    public init(
        expanding ids: [Int], imageTokenID: Int, grids: [Qwen3VLImageGrid], mergeSize: Int
    ) throws {
        let pads = ids.filter { $0 == imageTokenID }.count
        guard pads == grids.count else {
            throw Qwen3VLEncodingError.imagePadCountDisagrees(pads: pads, pictures: grids.count)
        }
        var expanded: [Int] = []
        var runs: [Range<Int>] = []
        var picture = 0
        expanded.reserveCapacity(ids.count)
        for id in ids {
            guard id == imageTokenID else {
                expanded.append(id)
                continue
            }
            let slots = grids[picture].slotCount(mergeSize: mergeSize)
            runs.append(expanded.count..<(expanded.count + slots))
            expanded.append(contentsOf: repeatElement(imageTokenID, count: slots))
            picture += 1
        }
        self.ids = expanded
        imageRuns = runs
    }

    /// Drops the first `count` tokens and moves every run back with them.
    ///
    /// This is `_drop_idx` applied to the layout rather than only to the hidden states: the
    /// image-pad mask the transformer reads is dropped by the same amount, and a run that is
    /// one token out puts a reference's tokens beside the wrong latents.
    public func droppingFirst(_ count: Int) -> Self {
        Self(
            ids: Array(ids.dropFirst(count)),
            imageRuns: imageRuns.compactMap { run in
                guard run.lowerBound >= count else { return nil }
                return (run.lowerBound - count)..<(run.upperBound - count)
            })
    }

    private init(ids: [Int], imageRuns: [Range<Int>]) {
        self.ids = ids
        self.imageRuns = imageRuns
    }
}
