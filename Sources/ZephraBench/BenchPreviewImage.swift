import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZephraCore

/// Writes one preview frame out as a PNG, so `--preview` can be looked at and not only timed.
///
/// A frame is the only part of a generation whose correctness a size assertion cannot reach: a
/// latent unpacked on the wrong axis order decodes to plausible-looking noise of exactly the
/// right dimensions. Writing the last frame beside the image makes that visible in one look.
enum BenchPreviewImage {
    /// Writes `preview` next to `output` as `<stem>-preview.png`, and returns where it went.
    static func write(_ preview: GenerationPreview, beside output: URL) throws -> URL {
        let url = output
            .deletingPathExtension()
            .appendingPathExtension("preview.png")
        guard preview.isWellFormed,
            let provider = CGDataProvider(data: preview.pixels as CFData),
            let image = CGImage(
                width: preview.width,
                height: preview.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: preview.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw BenchPreviewError.notAnImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BenchPreviewError.notWritten }
        return url
    }
}

/// Why a preview frame could not be written.
enum BenchPreviewError: Error {
    /// The bytes were not the length the frame's own size says they are.
    case notAnImage
    /// CoreGraphics refused the write.
    case notWritten
}
