import Foundation

/// One frame of a generation still in flight: the latent as it stood after some step, decoded
/// small enough to be cheap.
///
/// Deliberately raw pixels rather than PNG bytes. A frame is looked at once, by one view, a
/// second or so after it was made; encoding it would cost more than the decode that produced
/// it, and every reader would have to decode it straight back.
///
/// Deliberately not `Hashable` either. It is carried inside `GenerationProgressEvent`, which is
/// carried inside `EngineState`, and hashing a quarter of a megabyte of pixels on every state
/// comparison would be a real cost for an answer nobody wants: two frames of the same run are
/// different pictures, not different states. `GenerationProgressEvent` ignores it in both.
public struct GenerationPreview: Sendable {
    /// Pixels across.
    public let width: Int
    /// Pixels down.
    public let height: Int
    /// `width * height * 4` bytes, RGBA8, row-major, **straight alpha** and never
    /// premultiplied; 255 everywhere for every model that does not make transparency.
    public let pixels: Data
    /// What this frame cost to make: the pooled decode, measured by whoever ran it.
    ///
    /// It rides along because it is a property of the frame rather than of the run, and because
    /// it is what `ZephraBench --preview` averages and what the throttle interval is tuned
    /// against. Nothing on screen reads it.
    public let duration: Duration

    /// Creates a frame. `pixels` is trusted to be `width * height * 4` bytes long.
    public init(width: Int, height: Int, pixels: Data, duration: Duration = .zero) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.duration = duration
    }

    /// Whether the buffer is the length the size claims, which is what a reader building an
    /// image from it must check before it trusts the bytes.
    public var isWellFormed: Bool {
        width > 0 && height > 0 && pixels.count == width * height * 4
    }

    /// Whether any pixel is less than opaque, which decides the ground drawn under the frame
    /// and whether the JPEG a phone is sent has to be composited first.
    ///
    /// The bytes themselves, because a frame has no file and no descriptor with it: one pass
    /// over every fourth byte of at most 512 pixels an edge, which is 262,144 comparisons for
    /// the largest frame the engine sends. It is read once per frame, beside the image that
    /// frame is made into, and never inside a `body`.
    public var hasTransparency: Bool {
        guard isWellFormed else { return false }
        return pixels.withUnsafeBytes { buffer in
            var index = 3
            while index < buffer.count {
                if buffer[index] != 255 { return true }
                index += 4
            }
            return false
        }
    }
}
