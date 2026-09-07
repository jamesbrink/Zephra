import CoreGraphics
import Foundation
import MLX

/// The picture a clip is held from, turned into the video encoder's input.
///
/// It takes a `CGImage`; reading one off disk is the backend's job, not the kit's, so nothing
/// here opens a file. The other direction — the decoder's output as an MP4 or as a preview
/// frame's bytes — is `LTX2Frames` and `LTX2LatentPreview`.
///
/// The picture is scaled to **cover** the clip and cropped to the middle, not stretched and not
/// letterboxed. Letterboxing is what the smaller of the two ratios would do, and the bars it
/// leaves are not neutral: they encode as a stripe at -1 down two edges, which the model holds
/// as faithfully as it holds the picture and then continues into every frame after it.
/// Stretching keeps every pixel but hands the model a first frame whose proportions the rest of
/// the clip has no reason to keep. Covering loses the edges of one axis, which is what a person
/// choosing a picture for a clip of another shape expects.
public enum LTX2FirstFramePixels {
    /// Draws `image` at `width` by `height` and returns it the way the encoder wants it.
    ///
    /// - Returns: `[1, 3, 1, height, width]` in the range -1 to 1 — channels first and one
    ///   frame, which is a clip of a single picture and encodes to a single latent frame.
    public static func pixels(from image: CGImage, width: Int, height: Int) throws -> MLXArray {
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
            context.interpolationQuality = .high
            context.draw(image, in: Self.fill(image, width: width, height: height))
            return true
        }
        guard drawn else { throw LTX2PipelineError.unreadableFirstFrame }

        let rgba = MLXArray(bytes, [1, height, width, 4]).asType(.float32)
        let rgb = rgba[.ellipsis, 0..<3] / 127.5 - 1
        return rgb.transposed(0, 3, 1, 2).expandedDimensions(axis: 2)
    }

    /// Where to draw `image` so it covers a `width` by `height` frame, centred: the **larger**
    /// of the two ratios, so the overflow is clipped by the bitmap rather than left as bars.
    static func fill(_ image: CGImage, width: Int, height: Int) -> CGRect {
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        return CGRect(
            x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2,
            width: drawn.width, height: drawn.height)
    }
}
