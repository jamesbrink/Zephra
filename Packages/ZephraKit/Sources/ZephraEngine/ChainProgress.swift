import Foundation
import ZephraCore

/// A chained clip on its way: the passes planned, the segments made so far, and the clip it
/// began from, if it carries one on.
struct ChainProgress: Sendable {
    /// The length of every pass, in frames.
    let segments: [Int]
    /// The clip the first pass carried on, when the chain was made by Extend Clip with a
    /// length past one pass; nil for a chain from nothing or from a picture.
    let source: ClipContinuation?
    /// The segments made so far, each with the frames it held from the one before, oldest
    /// first.
    var parts: [ClipPart] = []
    /// The first segment's poster, which is the whole clip's.
    var poster: Data?
    /// Time spent generating and joining earlier passes, excluding time waiting in the queue.
    var elapsed: Duration = .zero
    var executionElapsed: Duration = .zero
    var timingKey: WorkloadTimingKey?

    init(segments: [Int], source: ClipContinuation?) {
        self.segments = segments
        self.source = source
    }
}
