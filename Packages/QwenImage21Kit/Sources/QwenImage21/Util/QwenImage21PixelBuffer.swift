import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers
import ZephraMLX

/// A four-channel decode turned into bytes: a PNG for the library, or raw RGBA8 for a preview
/// frame.
///
/// **This is `ZephraMLX.PixelBuffer` with the alpha channel carried rather than invented, and
/// it exists only until the shared one learns four channels.** That change is owned by another
/// slice, and the contract it lands with is the one implemented here:
///
/// ```swift
/// // `pixels` is [batch, height, width, channels] in the range -1 to 1, channels 3 or 4.
/// // At 4 channels the fourth is straight (non-premultiplied) alpha, scaled and rounded the
/// // same way the colour channels are, and the PNG is written with CGImageAlphaInfo.last
/// // rather than .noneSkipLast. At 3 channels nothing changes.
/// public static func png(from pixels: MLXArray) throws -> Data
/// public static func rgba8(_ pixels: MLXArray) -> Data
/// ```
///
/// When that lands, **delete this file** and call the shared one; `PixelBufferTests` pins the
/// same bytes either way, so the swap is checked rather than assumed. Until then the shared
/// `rgba8` cannot be used for 2.1 at all: it appends an opaque alpha column unconditionally,
/// which over four channels would make five.
///
/// A channel value lands on the **nearest** byte, `(x + 1) * 127.5` rounded before it is
/// clipped and cast, which is what `diffusers` does (`(image * 255).round()`) and what the
/// shared buffer already does; a plain cast truncates and pulls every channel down by up to one
/// step of 255. Alpha goes through the same arithmetic as the colours, so a fully transparent
/// pixel at -1 is 0 and a fully opaque one at 1 is 255.
public enum QwenImage21PixelBuffer {
    /// Encodes `pixels`, `[batch, height, width, 4]` in the range -1 to 1, as an RGBA PNG.
    public static func png(from pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.dim(0), image.dim(1))
        let bytes = rgba8(pixels)

        guard
            let provider = CGDataProvider(data: bytes as CFData),
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                // Straight alpha, last: the decode is not premultiplied, and saying `.last`
                // over premultiplied bytes -- or `.premultipliedLast` over these -- darkens or
                // lightens every partly transparent pixel.
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { throw PixelBufferError.encodingFailed }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { throw PixelBufferError.encodingFailed }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PixelBufferError.encodingFailed
        }
        return output as Data
    }

    /// The first picture of `pixels`, `[batch, height, width, 4]` in the range -1 to 1, as
    /// RGBA8 bytes: row-major, four to a pixel, the fourth the picture's own alpha.
    public static func rgba8(_ pixels: MLXArray) -> Data {
        let scaled = clip(
            round((pixels[0] + 1) * 127.5), min: MLXArray(Float(0)), max: MLXArray(Float(255)))
        eval(scaled)
        return scaled.asType(.uint8).asData().data
    }
}
