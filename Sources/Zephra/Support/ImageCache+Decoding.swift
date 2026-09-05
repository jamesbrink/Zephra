import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// The Image I/O half: bytes to a `CGImage`, and the digest a reference is filed under.
///
/// All of it is `nonisolated` and static. None of it touches the cache's state, and every
/// call is made from inside a detached task, which is the point: a decode must never happen
/// on the main actor, and the type system should be the thing that says so.
extension ImageCache {
    /// The longest edge of a filmstrip thumbnail, in pixels, at 2x for Retina.
    nonisolated static let thumbnailPixels = 288

    /// Pixels for `data` at `kind`, or nil when the bytes are not a picture macOS can read.
    ///
    /// `ShouldCacheImmediately` decodes here, in this task, rather than lazily on whichever
    /// thread first draws the pixels — which would be the main one. The thumbnail is built by
    /// Image I/O at its final size, so the full-resolution bitmap is never made for it.
    nonisolated static func decode(_ data: Data, _ kind: Kind) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        switch kind {
        case .full:
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        case .thumbnail:
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
            ] as CFDictionary)
        }
    }

    /// The SHA-256 of `data`, as hex.
    nonisolated static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
