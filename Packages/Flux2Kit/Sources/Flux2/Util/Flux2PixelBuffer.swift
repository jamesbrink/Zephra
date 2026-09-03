import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers

/// Turning the decoder's output into PNG bytes, and a picture's bytes into the decoder's input.
public enum Flux2PixelBuffer {
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
        else { throw Flux2PipelineError.encodingFailed }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { throw Flux2PipelineError.encodingFailed }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Flux2PipelineError.encodingFailed
        }
        return output as Data
    }
}
