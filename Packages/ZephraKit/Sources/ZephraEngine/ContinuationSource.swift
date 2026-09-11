import Foundation
import ZephraCore

/// The clip Extend Clip is asked to carry on: where its MP4 is, and what its record says.
///
/// A clip on disk is read by URL; one this session made and has not finished writing is read
/// from the bytes still in memory, so a clip can be extended the moment it is on the canvas.
/// `origin` is the poster's library file name, which the stitch resolves the source by again
/// when the segment lands and the record writes down as `continuedFrom`.
public struct ContinuationSource: Sendable {
    /// Where the clip's frames are.
    public enum Clip: Sendable {
        /// The MP4 beside the poster on disk.
        case file(URL)
        /// The MP4 still in memory, not yet written.
        case bytes(Data)
    }

    /// The poster's library file name.
    public var origin: String
    /// The clip's frames.
    public var clip: Clip
    /// What made the clip: its prompt, size, model and length.
    public var record: GenerationRecord

    public init(origin: String, clip: Clip, record: GenerationRecord) {
        self.origin = origin
        self.clip = clip
        self.record = record
    }
}
