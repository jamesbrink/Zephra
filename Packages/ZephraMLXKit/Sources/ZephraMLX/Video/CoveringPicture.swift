import CoreGraphics
import Foundation
import MLX

/// A picture drawn to cover a frame of another shape, as a video encoder's input.
///
/// It takes a `CGImage`; reading one off disk is a backend's job, not a kit's, so nothing here
/// opens a file.
///
/// The picture is scaled to **cover** the frame and cropped to the middle, not stretched and not
/// letterboxed. Letterboxing is what the smaller of the two ratios would do, and the bars it
/// leaves are not neutral: they encode as a stripe at one end of the range down two edges,
/// which a model holds as faithfully as it holds the picture and then continues into every
/// frame after it. Stretching
/// keeps every pixel but hands the model a first frame whose proportions the rest of the clip
/// has no reason to keep. Covering loses the edges of one axis, which is what a person choosing
/// a picture for a clip of another shape expects.
public enum CoveringPicture {
    /// Draws `image` at `width` by `height`.
    ///
    /// - Returns: `[1, height, width, 3]` in the range -1 to 1, or nil when CoreGraphics would
    ///   not draw into a bitmap of that size.
    public static func pixels(from image: CGImage, width: Int, height: Int) -> MLXArray? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            // Cleared to **white**, not to the zeroes a fresh bitmap holds: a reference
            // picture may carry transparency now, and a matte decides what its clear pixels
            // encode as. Black was what an uncleared buffer happened to give; white is what
            // a person expects and what the 2.1 pipeline prescribes for its own references.
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Plain bilinear, not `.high`'s anti-aliased downsample: diffusers' LTX condition
            // pipeline deliberately skips `VideoProcessor.preprocess_video`, whose PIL resize
            // applies an anti-aliasing pre-filter, and reproduces the original code's plain
            // `F.interpolate(..., mode="bilinear")`; `.default` is CoreGraphics' own bilinear.
            context.interpolationQuality = .default
            context.draw(image, in: Self.fill(image, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let rgba = MLXArray(bytes, [1, height, width, 4]).asType(.float32)
        return rgba[.ellipsis, 0..<3] / 127.5 - 1
    }

    /// Where to draw `image` so it covers a `width` by `height` frame, centred: the **larger**
    /// of the two ratios, so the overflow is clipped by the bitmap rather than left as bars.
    public static func fill(_ image: CGImage, width: Int, height: Int) -> CGRect {
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        return CGRect(
            x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2,
            width: drawn.width, height: drawn.height)
    }
}
