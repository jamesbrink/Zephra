import CoreGraphics
import Foundation
import ImageIO

/// Reading a reference picture as something the pipeline can encode.
nonisolated enum ReferenceImageDecoding {
    /// What went wrong reading a reference, worded for someone who chose the picture.
    enum Failure: Error, LocalizedError {
        case undecodable

        var errorDescription: String? {
            switch self {
            case .undecodable: "The reference image could not be read."
            }
        }
    }

    /// The first image in `data`.
    ///
    /// ImageIO, not AppKit, because this runs on the inference queue rather than the main
    /// actor, and because a backend package may not import a UI framework. Whatever ImageIO
    /// reads is accepted — the interface hands over PNG, but the decode does not insist on it.
    /// Resizing to the generation's size is the pipeline's job, so nothing is scaled here.
    ///
    /// Bytes, not a URL: settings carry the picture itself, so that a queued edit still means
    /// the same picture twenty minutes later whatever has happened to the file it came from.
    static func cgImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.undecodable }
        return image
    }
}
