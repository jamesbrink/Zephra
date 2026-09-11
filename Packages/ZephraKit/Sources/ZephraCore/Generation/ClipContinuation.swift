import Foundation

/// The tail of a finished clip, handed to the next generation so it carries on from where the
/// clip ends: the last frames as pictures, and which library clip they came out of.
///
/// Pictures rather than a latent, because nothing crosses the backend seam but bytes: a backend
/// is stateless and `GeneratedMedia` is an MP4, so the previous clip's end has to go back in
/// the same way a reference picture does. Both video families encode the frames with their
/// causal autoencoder and hold the result at the head of the new clip; how many they hold is
/// `ModelCapabilities.continuationFrames`, and a family that can hold only one takes the last.
///
/// Bytes and not a file URL, for the reason `GenerationSettings.referenceImage` gives: a queue
/// entry must mean the same clip twenty minutes later, after the source has been moved or
/// deleted. The pixels are dropped from the settings a finished image is published with
/// (`withoutPixels`), so history never holds a clip's tail.
public struct ClipContinuation: Hashable, Sendable, Codable {
    /// The clip's last frames, oldest first, as PNG bytes; the last element is the frame the
    /// clip ends on. The count is on the continuing model's ladder, `1 + k * frameAlignment`.
    public var frames: [Data]
    /// The library file name of the clip being continued, the poster PNG's, so the result can
    /// be stitched onto it and its record can say what it continues; nil for a segment of a
    /// chained clip, which carries on from a segment still in memory rather than from a file.
    public var origin: String?
    /// How many frames the clip being continued has, so the stitched clip's length is known
    /// before the source is read again.
    public var sourceFrameCount: Int
    /// How many frames the backend holds: `frames.count`, kept as a number of its own so it
    /// survives `withoutPixels` and the record can still say how many were held.
    public private(set) var contextFrames: Int

    public init(frames: [Data], origin: String?, sourceFrameCount: Int) {
        self.frames = frames
        self.origin = origin
        self.sourceFrameCount = sourceFrameCount
        self.contextFrames = frames.count
    }

    /// The same continuation with its pictures dropped: what a finished image keeps, so the
    /// record can still say what it continued without history holding the frames.
    public func withoutPixels() -> ClipContinuation {
        var copy = self
        copy.frames = []
        return copy
    }

    /// The last `count` frames, or all of them when there are fewer: what `clamp` hands a
    /// model that holds less context than was read.
    public func keepingLast(_ count: Int) -> ClipContinuation {
        guard count < frames.count else { return self }
        return ClipContinuation(
            frames: Array(frames.suffix(max(count, 0))), origin: origin,
            sourceFrameCount: sourceFrameCount)
    }
}
