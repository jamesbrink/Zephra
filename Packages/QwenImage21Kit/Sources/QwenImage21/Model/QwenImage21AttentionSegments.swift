import Foundation

/// The block-causal mask in the form an attention kernel can run without a mask kernel.
///
/// Attention follows `(q >= kv) or same image block`: the joint sequence is causal, every image
/// block is internally bidirectional, and a later block sees every earlier one. Written as a
/// dense mask that is a score matrix the size of the sequence squared; written as segments it
/// is a handful of ordinary attention calls.
///
/// The prefix — everything before the image being made — splits into runs of equal
/// `imageIDs`. Each run attends over the keys `[0, end)`: everything before it plus its own
/// block. A **text** run additionally gets a causal triangle over its own keys, which is
/// exactly a causal mask aligned to the bottom right of `[end - start, end]`. The target's
/// queries then attend over the whole sequence with no mask at all.
///
/// Text-to-image with an unpadded prompt is therefore **two** attention calls per layer on the
/// first step — one causal over the text, one full for the target — and **one** on every step
/// after it, over the cached prefix.
public struct QwenImage21AttentionSegments: Sendable {
    /// One run of the prefix.
    public struct Segment: Hashable, Sendable {
        /// First query of the run.
        public let start: Int
        /// One past its last query, and also how many keys it attends over.
        public let end: Int
        /// Whether the run is text, and so causal within itself.
        public let isText: Bool

        /// One run.
        public init(start: Int, end: Int, isText: Bool) {
            self.start = start
            self.end = end
            self.isText = isText
        }
    }

    /// The runs, in sequence order.
    public let segments: [Segment]

    /// How far the segments reach, which is the prefix.
    public var prefixLength: Int { segments.last?.end ?? 0 }

    /// Splits `imageIDs[0..<prefixLength]` into runs of equal id.
    public init(imageIDs: [Int], prefixLength: Int) {
        guard prefixLength > 0 else {
            segments = []
            return
        }
        var runs: [Segment] = []
        var start = 0
        for index in 1...prefixLength where index == prefixLength || imageIDs[index] != imageIDs[start] {
            runs.append(Segment(start: start, end: index, isText: imageIDs[start] < 0))
            start = index
        }
        segments = runs
    }

    /// The runs of `layout`'s prefix.
    public init(_ layout: QwenImage21JointLayout) {
        self.init(imageIDs: layout.imageIDs, prefixLength: layout.prefixLength)
    }
}
