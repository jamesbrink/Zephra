import CoreGraphics
import Foundation
import ImageIO
import ZephraCore

/// Reading a reference picture off disk as something the pipeline can encode.
nonisolated enum ReferenceImageDecoding {
    /// What went wrong reading a reference, worded for someone looking at their own file.
    enum Failure: Error, LocalizedError {
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                "Could not read the reference image at \(url.path(percentEncoded: false))."
            }
        }
    }

    /// The first image in the file at `url`.
    ///
    /// ImageIO, not AppKit, because this runs on the inference queue rather than the main
    /// actor, and because the backend package may not import a UI framework. Whatever ImageIO
    /// reads is accepted — the library writes PNG, but a JPEG dropped in by hand works too.
    /// Resizing to the generation's size is the pipeline's job, so nothing is scaled here.
    static func cgImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable(url) }
        return image
    }
}
