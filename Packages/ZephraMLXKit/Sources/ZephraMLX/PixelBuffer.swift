import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers

/// Turning an autoencoder's output into bytes: a PNG for the library, or raw RGBA8 for a
/// preview frame.
///
/// Every autoencoder the app ships decodes to `[batch, height, width, 3]` in the range -1 to 1,
/// so the way out to a byte is the same job for each of them. Reading a picture *in* is not
/// shared: each family fits a reference to its own grid, and that stays in the kit.
///
/// A channel value lands on the **nearest** byte. `(x + 1) * 127.5` is rounded before it is
/// clipped and cast, as `diffusers` rounds (`(image * 255).round()`); a plain cast truncates,
/// which pulls every channel of every pixel down by up to one step of 255.
public enum PixelBuffer {
    /// Encodes `pixels`, `[batch, height, width, 3]` in the range -1 to 1, as PNG.
    public static func png(from pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.shape[0], image.shape[1])
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
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
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

    /// The first image of `pixels`, `[batch, height, width, 3]` in the range -1 to 1, as RGBA8
    /// bytes: row-major, four to a pixel, opaque.
    public static func rgba8(_ pixels: MLXArray) -> Data {
        let image = pixels[0]
        let (height, width) = (image.dim(0), image.dim(1))
        let scaled = MLX.clip(
            MLX.round((image + 1) * 127.5), min: MLXArray(Float(0)), max: MLXArray(Float(255)))
        let opaque = MLX.concatenated(
            [scaled, MLXArray.full([height, width, 1], values: MLXArray(Float(255)))], axis: -1)
        MLX.eval(opaque)
        return opaque.asType(.uint8).asData().data
    }
}
