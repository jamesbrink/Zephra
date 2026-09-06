import Foundation

/// A clip's pixels before encoding: every frame's RGBA8 bytes, row-major, laid end to end.
///
/// One contiguous buffer rather than an array of frames, because that is what a decoder
/// hands back and what an encoder walks; a frame is `frameBytes` at `frame * frameBytes`.
public struct RGBAFrameSequence: Sendable {
    /// Pixels across one frame.
    public let width: Int
    /// Pixels down one frame.
    public let height: Int
    /// How many frames `pixels` holds.
    public let frameCount: Int
    /// `frameCount * width * height * 4` bytes of RGBA8.
    public let pixels: Data

    /// Creates a sequence, refusing a buffer whose length does not match its shape.
    public init(width: Int, height: Int, frameCount: Int, pixels: Data) throws {
        guard width > 0, height > 0, frameCount > 0 else {
            throw MP4WriterError.emptyClip
        }
        guard pixels.count == width * height * 4 * frameCount else {
            throw MP4WriterError.pixelCountMismatch(
                expected: width * height * 4 * frameCount, got: pixels.count)
        }
        self.width = width
        self.height = height
        self.frameCount = frameCount
        self.pixels = pixels
    }

    /// Bytes in one frame.
    public var frameBytes: Int { width * height * 4 }

    /// The bytes of frame `index`.
    public func frame(_ index: Int) -> Data {
        let start = pixels.startIndex + index * frameBytes
        return pixels[start..<start + frameBytes]
    }
}
