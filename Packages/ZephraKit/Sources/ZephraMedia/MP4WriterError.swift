import Foundation

/// What can go wrong turning frames into a file, or reading them back out of one.
public enum MP4WriterError: Error, Equatable, Sendable {
    /// No frames, or a frame with no pixels.
    case emptyClip
    /// The pixel buffer is not `width * height * 4 * frames` bytes.
    case pixelCountMismatch(expected: Int, got: Int)
    /// AVFoundation refused to start, append to, or finish the file; the text is its own.
    case encodingFailed(String)
    /// The file has no video track to read.
    case notAClip
    /// Two clips being joined do not share a frame size and rate.
    case mismatchedParts
}
