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
    /// Alpha is `premultipliedLast` because the frame is opaque: every byte of the fourth
    /// channel is 255, which makes premultiplied and straight the same bytes, and saying so
    /// spares Core Graphics a conversion.
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
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
