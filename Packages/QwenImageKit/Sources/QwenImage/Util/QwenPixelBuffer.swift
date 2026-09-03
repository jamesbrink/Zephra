import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers

/// Turning the decoder's output into PNG bytes, and a picture back into the encoder's input.
public enum QwenPixelBuffer {
    /// The first image in the file at `url`, unscaled.
    ///
    /// ImageIO rather than AppKit, so this can be called off the main actor and from a package
    /// that must not import a UI framework. Whatever ImageIO reads is accepted.
    public static func image(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw QwenImagePipelineError.referenceUnreadable(url) }
        return image
    }

    /// Draws `image` at `width` by `height` and returns it the way the encoder wants it.
    ///
    /// - Returns: `[1, height, width, 3]` in the range -1 to 1, which is `png(from:)`'s input
    ///   scale and shape, so a picture that goes through `encode` and back out of `decode`
    ///   arrives in the units it left in.
    ///
    /// The reference does not care how the picture is scaled to the generation's size, and this
    /// takes CoreGraphics' default resampling, which fills the frame — a reference of a
    /// different aspect ratio is stretched rather than cropped or letterboxed. Cropping is a
    /// decision for whoever chose the picture, not for the encoder.
    public static func pixels(from image: CGImage, width: Int, height: Int) throws -> MLXArray {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw QwenImagePipelineError.encodingFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { throw QwenImagePipelineError.encodingFailed }

        let count = width * height * 4
        let buffer = UnsafeBufferPointer(
            start: bytes.assumingMemoryBound(to: UInt8.self), count: count)
        let rgba = MLXArray(Array(buffer)).reshaped([1, height, width, 4])
        let rgb = rgba[0..., 0..., 0..., 0 ..< 3].asType(.float32)
        return rgb / MLXArray(Float(127.5)) - MLXArray(Float(1))
    }

    /// Encodes `pixels`, `[batch, height, width, 3]` in the range -1 to 1, as PNG.
    public static func png(from pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.shape[0], image.shape[1])

        // -1...1 to 0...255, with an opaque alpha channel, which is what CoreGraphics wants.
        let scaled = MLX.clip((image + 1) * 127.5, min: MLXArray(Float(0)), max: MLXArray(Float(255)))
        let opaque = MLX.concatenated(
            [scaled, MLXArray.full([height, width, 1], values: MLXArray(Float(255)))], axis: -1)
        MLX.eval(opaque)
        let bytes = opaque.asType(.uint8).asData().data

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
        else { throw QwenImagePipelineError.encodingFailed }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { throw QwenImagePipelineError.encodingFailed }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw QwenImagePipelineError.encodingFailed
        }
        return output as Data
    }
}
