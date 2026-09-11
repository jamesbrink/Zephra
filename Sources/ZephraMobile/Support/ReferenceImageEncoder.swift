import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZephraCore

/// Turns whatever picture somebody hands over — a photo out of the camera roll, a picture
/// fetched back off the Mac — into the PNG bytes a reference is carried as.
///
/// The Mac's encoder of the same name, on the phone, and for the same two reasons: one place
/// decides what a reference *is*, and one place decides how big it may be. It is `nonisolated`
/// throughout so a five-megapixel photo is resized off the main actor; a door that called it
/// there would freeze the capsule while somebody watched.
enum ReferenceImageEncoder {
    /// The most pixels worth carrying along an edge, which is the cap `GenerationSettings`
    /// documents and the most any of the models reads.
    nonisolated static let maximumPixelsPerEdge = 1024

    /// The picture in `data` as PNG inside the budget, or nil when the bytes are not a picture
    /// this phone can read.
    nonisolated static func picture(from data: Data) -> ReferencePicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return picture(from: source)
    }

    /// The picture at `url`, read from disk rather than held in memory first.
    nonisolated static func picture(contentsOf url: URL) -> ReferencePicture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return picture(from: source)
    }

    private nonisolated static func picture(from source: CGImageSource) -> ReferencePicture? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // A photo taken sideways is the classic mistake; honour its orientation.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelsPerEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ReferencePicture(
            data: output as Data, size: ImageSize(width: image.width, height: image.height))
    }
}
