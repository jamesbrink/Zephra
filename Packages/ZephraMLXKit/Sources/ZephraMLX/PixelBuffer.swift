import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers

/// Turning an autoencoder's output into bytes: a PNG for the library, or raw RGBA8 for a
/// preview frame.
///
/// Every autoencoder the app ships decodes to `[batch, height, width, channels]` in the range
/// -1 to 1, so the way out to a byte is the same job for each of them. Reading a picture *in*
/// is not shared: each family fits a reference to its own grid, and that stays in the kit.
///
/// **Three channels or four.** Three is a picture with no transparency and is written exactly
/// as it always has been, an opaque byte appended per pixel and the alpha skipped in the
/// encode. Four is a model that decodes transparency, and its fourth channel is packed as it
/// stands: **straight alpha, never premultiplied**, because that channel came out of the
/// autoencoder in -1 to 1 like the other three and premultiplying would be a separate multiply
/// that loses colour in every near-transparent pixel. Any other width is a decode this does not
/// understand, and it throws rather than writing a wrong `bytesPerRow`.
///
/// A channel value lands on the **nearest** byte. `(x + 1) * 127.5` is rounded before it is
/// clipped and cast, as `diffusers` rounds (`(image * 255).round()`); a plain cast truncates,
/// which pulls every channel of every pixel down by up to one step of 255.
public enum PixelBuffer {
    /// Encodes `pixels`, `[batch, height, width, 3 or 4]` in the range -1 to 1, as PNG.
    public static func png(from pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.shape[0], image.shape[1])
        let bytes = try rgba8(pixels)
        let alpha: CGImageAlphaInfo = image.dim(2) == 4 ? .last : .noneSkipLast

        guard
            let provider = CGDataProvider(data: bytes as CFData),
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
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

    /// The first image of `pixels`, `[batch, height, width, 3 or 4]` in the range -1 to 1, as
    /// RGBA8 bytes: row-major, four to a pixel, straight alpha.
    ///
    /// Three channels are given an opaque fourth here; four are packed as they are. Anything
    /// else throws `PixelBufferError.unsupportedChannelCount`.
    public static func rgba8(_ pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width, channels) = (image.dim(0), image.dim(1), image.dim(2))
        guard channels == 3 || channels == 4 else {
            throw PixelBufferError.unsupportedChannelCount(channels)
        }
        let scaled = MLX.clip(
            MLX.round((image + 1) * 127.5), min: MLXArray(Float(0)), max: MLXArray(Float(255)))
        let packed = channels == 4
            ? scaled
            : MLX.concatenated(
                [scaled, MLXArray.full([height, width, 1], values: MLXArray(Float(255)))],
                axis: -1)
        MLX.eval(packed)
        return packed.asType(.uint8).asData().data
    }
}
