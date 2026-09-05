import CoreGraphics
import Foundation
import ImageIO
import MLX

/// A reference picture's bytes turned into the autoencoder's input.
///
/// The other direction — the decoder's output as PNG or as a preview frame's bytes — is
/// `PixelBuffer` in `ZephraMLX`, the same for every family. This half stays here because the
/// size a picture is fitted to is this model's own rule.
public enum Flux2PixelBuffer {
    /// Decodes a picture's bytes into `[1, 3, height, width]` in the range -1 to 1, scaled to
    /// cover at most a megapixel and cropped so each edge is a multiple of `alignment`.
    ///
    /// Channels first, as the reference and the autoencoder's encoder speak; the autoencoder
    /// moves to channels-last itself. The scale is done by Core Graphics on the way into the
    /// bitmap, which is one resample rather than a decode and a resize.
    public static func pixels(from data: Data, alignment: Int) throws -> MLXArray {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary)
        else { throw Flux2PipelineError.unreadableReference }

        let target = Flux2ImageFitting.target(
            width: image.width, height: image.height, alignment: alignment)
        let (width, height) = (target.width, target.height)
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
            // Scale so the picture covers the fitted size and centre it: the trim to a
            // multiple of sixteen comes off both edges equally, and the overflow is clipped by
            // the bitmap. The larger ratio, not the smaller, or the trim would become black
            // bars down one edge that encode as a stripe of -1.
            let scale = max(
                Double(width) / Double(image.width), Double(height) / Double(image.height))
            let drawnWidth = Double(image.width) * scale
            let drawnHeight = Double(image.height) * scale
            context.draw(
                image,
                in: CGRect(
                    x: (Double(width) - drawnWidth) / 2, y: (Double(height) - drawnHeight) / 2,
                    width: drawnWidth, height: drawnHeight))
            return true
        }
        guard drawn else { throw Flux2PipelineError.unreadableReference }

        let rgba = MLXArray(bytes, [1, height, width, 4]).asType(.float32)
        let rgb = rgba[.ellipsis, 0..<3]
        return (rgb / 127.5 - 1).transposed(0, 3, 1, 2)
    }
}
