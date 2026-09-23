import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZephraCore

/// Turns whatever picture the user hands over into the PNG bytes a reference is carried as.
///
/// The one place a JPEG, HEIC, or TIFF becomes PNG, and the one place the size is decided.
/// Nothing above `Sources/Zephra` ever sees an image type: the engine and the model packages
/// deal in bytes, and it is this file that decides what those bytes are.
enum ReferenceImageEncoder {
    /// The most pixels worth carrying along an edge. FLUX.2 klein fits a reference into
    /// 1024x1024 worth of pixels before it encodes one, so anything larger is bytes the app
    /// would hold in memory, hash, write into every saved PNG, and ship across an actor
    /// boundary for nothing. The multiple-of-16 crop is the model's own, because the latent
    /// grid depends on it; this only bounds the size.
    nonisolated static let maximumPixelsPerEdge = 1024

    /// PNG bytes for the picture in `data`, scaled down to the budget, or nil when the bytes
    /// are not a picture macOS can read.
    nonisolated static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pngData(from: source)
    }

    /// PNG bytes for the picture at `url`, read from disk rather than held in memory first.
    nonisolated static func pngData(contentsOf url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pngData(from: source)
    }

    /// The whole picture a reference is: the bytes, where they came from, and what shape they
    /// are, measured here because here is where the scaling happened.
    ///
    /// `ReferencePicture.size` is stored rather than read back out of the PNG at every site that
    /// asks, so the one place that already knows it is the one place that fills it in.
    nonisolated static func picture(from data: Data, origin: String? = nil) -> ReferencePicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return picture(from: source, origin: origin)
    }

    /// The same over a file on disk, read rather than held in memory first.
    nonisolated static func picture(contentsOf url: URL, origin: String? = nil) -> ReferencePicture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return picture(from: source, origin: origin)
    }

    private nonisolated static func picture(
        from source: CGImageSource, origin: String?
    ) -> ReferencePicture? {
        guard let image = thumbnail(from: source), let data = encode(image) else { return nil }
        return ReferencePicture(
            data: data, origin: origin,
            size: ImageSize(width: image.width, height: image.height))
    }

    private nonisolated static func pngData(from source: CGImageSource) -> Data? {
        guard let image = thumbnail(from: source) else { return nil }
        return encode(image)
    }

    /// The picture scaled into the budget, with a sideways phone photo turned the right way up.
    private nonisolated static func thumbnail(from source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // A phone photo dropped in sideways is the classic mistake; honour its orientation.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelsPerEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
