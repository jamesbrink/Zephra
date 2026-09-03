import AppKit
import CryptoKit
import Foundation
import ZephraCore

/// Decoded pixels for the images this session produced, keyed by image identity.
///
/// PNG bytes are decoded exactly once per image, and thumbnails are built by Image I/O at
/// their final size rather than by scaling a full-resolution bitmap. Views look pixels up
/// here; they never decode inside `body`.
@Observable
final class ImageCache {
    /// The longest edge of a filmstrip thumbnail, in pixels, at 2x for Retina.
    private static let thumbnailPixels = 288

    private let fullSize = NSCache<NSUUID, NSImage>()
    private let thumbnails = NSCache<NSUUID, NSImage>()
    private let references = NSCache<NSString, NSImage>()

    /// Creates an empty cache. One instance lives for the life of the window.
    init() {
        fullSize.countLimit = 8
        thumbnails.countLimit = 64
        references.countLimit = 4
    }

    /// A small bitmap for the reference well, keyed by a digest of the bytes: a reference has
    /// no session identity of its own, and the same picture dropped twice is the same key.
    /// A digest and not `hashValue`, which reads only a prefix of a `Data` and would show the
    /// wrong picture for two files that agree on their first bytes.
    func thumbnail(forReference data: Data) -> NSImage? {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
        if let hit = references.object(forKey: key) { return hit }
        guard let made = Self.makeThumbnail(from: data) else { return nil }
        references.setObject(made, forKey: key)
        return made
    }

    /// The full-resolution bitmap for an image, decoding it the first time it is asked for.
    func fullSizeImage(for image: GeneratedImage) -> NSImage? {
        let key = image.id as NSUUID
        if let hit = fullSize.object(forKey: key) { return hit }
        guard let decoded = NSImage(data: image.pngData) else { return nil }
        fullSize.setObject(decoded, forKey: key)
        return decoded
    }

    /// A small bitmap for the filmstrip, built at thumbnail size by Image I/O.
    func thumbnail(for image: GeneratedImage) -> NSImage? {
        let key = image.id as NSUUID
        if let hit = thumbnails.object(forKey: key) { return hit }
        guard let made = Self.makeThumbnail(from: image.pngData) else { return nil }
        thumbnails.setObject(made, forKey: key)
        return made
    }

    private static func makeThumbnail(from data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
