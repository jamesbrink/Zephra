import CoreGraphics
import Foundation
import ImageIO
import ZephraCore

/// A frame of a generation that is not running, for the previews and the screenshot builds.
///
/// The real thing is a pooled latent put through the family's own autoencoder, which needs a
/// model and Metal. This is the same *shape* of thing arrived at the same way a pooled decode
/// arrives at it — a small RGBA8 buffer — by shrinking a drawn picture instead. It is what lets
/// `ZEPHRA_PREVIEW_STATE=generating` photograph the canvas as it looks while the model works,
/// on a machine with no weights on it.
extension PreviewImages {
    /// The long edge of a made-up frame, in pixels.
    ///
    /// Half of what a real one comes in at, which is the point: the canvas has to look right
    /// scaling a small frame up, not a nearly full-size one.
    private static let frameEdge = 128

    /// A drawn picture shrunk to a frame, or nil if Image I/O could not read the drawing back.
    static func frame(of image: GeneratedImage = sample()) -> GenerationPreview? {
        guard let small = thumbnail(of: image.pngData, edge: frameEdge),
              let pixels = rgba8(of: small)
        else { return nil }
        return GenerationPreview(width: small.width, height: small.height, pixels: pixels)
    }

    private static func thumbnail(of png: Data, edge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
        ]
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image's pixels as the opaque RGBA8 buffer a `GenerationPreview` carries.
    ///
    /// Through a context of our own rather than the image's own data provider, because the
    /// thumbnail comes back in whatever layout Image I/O found convenient and the frame's
    /// contract is exact: `width * height * 4` bytes, row-major, no padding.
    private static func rgba8(of image: CGImage) -> Data? {
        let (width, height) = (image.width, image.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { return nil }
        return Data(bytes: bytes, count: width * height * 4)
    }
}
