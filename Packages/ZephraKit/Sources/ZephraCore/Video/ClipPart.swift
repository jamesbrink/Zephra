import Foundation

/// One clip going into a stitch: its bytes and how many of its first frames to leave out.
///
/// A continuation's segment begins with the frames it was handed to hold, re-decoded; those
/// are the source clip's own last frames, so they are dropped and the join lands on the first
/// frame the model actually made.
public struct ClipPart: Hashable, Sendable {
    /// The clip, as an MP4.
    public var mp4: Data
    /// How many frames at the start to leave out of the result.
    public var dropLeading: Int

    public init(mp4: Data, dropLeading: Int = 0) {
        self.mp4 = mp4
        self.dropLeading = dropLeading
    }
}
