import CoreGraphics
import Foundation
import ImageIO
import MLX
import UniformTypeIdentifiers
import ZephraCore

/// PNG bytes in and PNG bytes out, at the network's own scale and layout.
///
/// The picture is drawn at its own size — an upscale must not resample its input, or the
/// enlargement would be of something other than what was asked for.
///
/// **Transparency is carried, not dropped.** A picture with an alpha channel is read into two
/// lanes: its colour, un-premultiplied back to the straight values the file held, and its alpha
/// on its own. The caller runs each through the network and hands both back to `png(from:_:)`,
/// which writes straight RGBA. A picture with no alpha channel takes the path it always did,
/// byte for byte, over a **white** matte rather than the black one it used to have — white is
/// what the 2.1 pipeline prescribes for a reference picture and what a person expects, and with
/// an opaque picture no matte is ever seen anyway.
public enum UpscalePixelBuffer {
    /// Decodes `png` into the network's input: `[1, height, width, 3]` float32 in 0...1, and
    /// the alpha beside it when the file carries one.
    public static func pixels(from png: Data) throws -> UpscaleInput {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw UpscaleError.failed("that file could not be read as a picture.") }

        let (width, height) = (image.width, image.height)
        guard width > 0, height > 0 else {
            throw UpscaleError.failed("that picture has no pixels.")
        }
        let transparent = carriesAlpha(image)
        let rgba = try drawn(image, width: width, height: height, keepingAlpha: transparent)
        guard transparent else {
            return UpscaleInput(rgb: rgba[.ellipsis, 0..<3] / 255, alpha: nil)
        }

        // A bitmap context cannot hold straight alpha, so the draw above premultiplied it.
        // Dividing it back out is what recovers the colour the file actually stored; a pixel
        // that is wholly clear has no colour to recover and is given white, which is the same
        // matte the opaque path uses and the one the enlarged alpha will hide anyway.
        let alpha = rgba[.ellipsis, 3..<4] / 255
        let colour = rgba[.ellipsis, 0..<3] / 255
        let straight = MLX.which(
            alpha .> MLXArray(Float(0)),
            colour / MLX.maximum(alpha, MLXArray(Float(1) / 255)),
            MLXArray(Float(1)))
        return UpscaleInput(
            rgb: MLX.clip(straight, min: MLXArray(Float(0)), max: MLXArray(Float(1))),
            alpha: alpha)
    }

    /// Encodes `pixels`, `[batch, height, width, 3]` in 0...1, as a PNG — opaque when `alpha`
    /// is nil, and straight RGBA when it is `[batch, height, width, 1]` in the same range.
    ///
    /// Clipped and rounded here rather than in the network, because the tiler's cross-fade is a
    /// weighted mean: a value clipped before the fade moves the seam instead of the pixel.
    public static func png(from pixels: MLXArray, _ alpha: MLXArray? = nil) throws -> Data {
        let image = pixels[0]
        let (height, width) = (image.dim(0), image.dim(1))
        let colour = byte(image)
        let fourth = alpha.map { byte($0[0]) }
            ?? MLXArray.full([height, width, 1], values: MLXArray(Float(255)))
        let packed = MLX.concatenated([colour, fourth], axis: -1)
        MLX.eval(packed)
        let bytes = packed.asType(.uint8).asData().data
        let info: CGImageAlphaInfo = alpha == nil ? .noneSkipLast : .last

        guard let provider = CGDataProvider(data: bytes as CFData),
            let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
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

    /// Whether the bitmap has an alpha channel at all.
    static func carriesAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        case .none, .noneSkipFirst, .noneSkipLast: false
        @unknown default: false
        }
    }

    /// `image` drawn at its own size into RGBA8, over white where the alpha is being dropped.
    private static func drawn(
        _ image: CGImage, width: Int, height: Int, keepingAlpha: Bool
    ) throws -> MLXArray {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let info: CGImageAlphaInfo = keepingAlpha ? .premultipliedLast : .noneSkipLast
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info.rawValue)
            else { return false }
            if !keepingAlpha {
                context.setFillColor(gray: 1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw UpscaleError.failed("that picture could not be drawn.") }
        return MLXArray(bytes, [1, height, width, 4]).asType(.float32)
    }

    /// One lane of 0...1 values as bytes, clipped and rounded the way the encoder wants.
    private static func byte(_ lane: MLXArray) -> MLXArray {
        MLX.round(MLX.clip(lane * 255, min: MLXArray(Float(0)), max: MLXArray(Float(255))))
    }
}
