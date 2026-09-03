import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers
import ZephraCore

/// PNG bytes in and PNG bytes out, at the network's own scale and layout.
///
/// The picture is drawn at its own size — an upscale must not resample its input, or the
/// enlargement would be of something other than what was asked for — into a `noneSkipLast` RGB
/// bitmap over black, and the result is written opaque. So **alpha is dropped**: every picture
/// this sees comes from the Zephra library, which is opaque by construction, and carrying a
/// transparency channel through a residual network that never learned one is out of scope for
/// v1. `ROADMAP.md` has it.
public enum UpscalePixelBuffer {
    /// Decodes `png` into `[1, height, width, 3]` float32 in 0...1, the range the network was
    /// trained on.
    public static func pixels(from png: Data) throws -> MLXArray {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw UpscaleError.failed("that file could not be read as a picture.") }

        let (width, height) = (image.width, image.height)
        guard width > 0, height > 0 else {
            throw UpscaleError.failed("that picture has no pixels.")
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw UpscaleError.failed("that picture could not be drawn.") }

        let rgba = MLXArray(bytes, [1, height, width, 4]).asType(.float32)
        return rgba[.ellipsis, 0..<3] / 255
    }

    /// Encodes `pixels`, `[batch, height, width, 3]` in 0...1, as an opaque PNG.
    ///
    /// Clipped and rounded here rather than in the network, because the tiler's cross-fade is a
    /// weighted mean: a value clipped before the fade moves the seam instead of the pixel.
    public static func png(from pixels: MLXArray) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.dim(0), image.dim(1))
        let scaled = MLX.round(
            MLX.clip(image * 255, min: MLXArray(Float(0)), max: MLXArray(Float(255))))
        let opaque = MLX.concatenated(
            [scaled, MLXArray.full([height, width, 1], values: MLXArray(Float(255)))], axis: -1)
        MLX.eval(opaque)
        let bytes = opaque.asType(.uint8).asData().data

        guard let provider = CGDataProvider(data: bytes as CFData),
            let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw UpscaleError.failed("the enlarged pixels could not be made into an image.") }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { throw UpscaleError.failed("a PNG could not be started.") }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.failed("the PNG could not be written.")
        }
        return output as Data
    }
}
