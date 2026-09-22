import CoreGraphics
import Foundation
import ZephraCore

/// Turning a frame of a generation in flight into something Core Graphics can draw.
///
/// The frame arrives as raw RGBA8 bytes rather than as a PNG, so there is nothing to decode:
/// the bytes are handed to a `CGDataProvider` as they stand and the image is a view onto them.
/// `Data` is copy-on-write, so the provider adds no copy of its own.
///
/// Callers keep the result rather than asking again inside `body`. A frame is a fixed thing —
/// new bytes are a new frame — so a view caches one image per frame in its own state and
/// rebuilds only when the bytes change.
extension GenerationPreview {
    /// The frame as an image, or nil when the buffer is not the length the size claims.
    ///
    /// Alpha is `last`, which is **straight** alpha: `PixelBuffer` packs a decode's fourth
    /// channel as it stands, and a model that makes transparency would have its near-clear
    /// pixels darkened by a `premultipliedLast` that was never true of the bytes. For every
    /// other model every fourth byte is 255, where straight and premultiplied are the same.
    func makeImage() -> CGImage? {
        guard isWellFormed, let provider = CGDataProvider(data: pixels as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Whether any pixel of the frame is less than opaque, which is what decides the ground
    /// drawn under it.
    ///
    /// The bytes themselves rather than a flag from the model, because a preview frame has no
    /// file and no descriptor with it. One pass over every fourth byte of at most 256 pixels
    /// an edge, which is 65,536 comparisons for the largest frame the engine sends, made once
    /// per frame beside the image it is made with and never inside `body`.
    var hasTransparency: Bool {
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
