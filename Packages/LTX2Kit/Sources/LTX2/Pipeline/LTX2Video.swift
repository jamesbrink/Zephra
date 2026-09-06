import Foundation

/// A decoded clip as bytes: every frame's RGBA8 pixels, row-major, laid end to end.
///
/// This is the kit's last word on a generation. The kit knows pixels and not containers, so
/// the MP4 is the backend's to write (through `ZephraMedia`), from exactly this layout: frame
/// `i` is `frameBytes` bytes at `i * frameBytes`.
public struct LTX2Video: Sendable, Hashable {
    /// Pixels across one frame.
    public let width: Int
    /// Pixels down one frame.
    public let height: Int
    /// How many frames `pixels` holds.
    public let frameCount: Int
    /// Frames per second the clip plays at.
    public let frameRate: Double
    /// `frameCount * width * height * 4` bytes of RGBA8, opaque.
    public let pixels: Data

    public init(width: Int, height: Int, frameCount: Int, frameRate: Double, pixels: Data) {
        precondition(pixels.count == width * height * 4 * frameCount, "pixels do not match the shape")
        self.width = width
        self.height = height
        self.frameCount = frameCount
        self.frameRate = frameRate
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
