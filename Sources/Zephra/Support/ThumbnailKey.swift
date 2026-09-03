import CryptoKit
import Foundation
import ZephraEngine

/// What one baked thumbnail is filed under: the file it came from, the state that file was in,
/// and the size it was baked at.
///
/// The modification date and the byte count are in the digest on purpose. A library item's
/// identity is its path, and a path can be reused — an image annotated, an image replaced by
/// another of the same name — so keying on the path alone would show yesterday's picture under
/// today's file. Including both means a changed file simply misses and is baked again, and the
/// stale entry is swept away in its own time rather than having to be found and deleted.
nonisolated struct ThumbnailKey: Hashable, Sendable {
    /// The digest, hex, truncated: sixteen bytes is far more than enough to keep a few thousand
    /// thumbnails apart, and a shorter name is a shorter path to open.
    let hex: String

    /// A key for one file in one state at one size.
    init(path: String, modifiedAt: Date, fileSize: Int64, pixels: Int) {
        let seconds = modifiedAt.timeIntervalSinceReferenceDate
        let material = "\(path)\n\(seconds)\n\(fileSize)\n\(pixels)"
        let digest = SHA256.hash(data: Data(material.utf8))
        hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The key for one library image at one size.
    init(_ item: LibraryItem, size: ThumbnailSize) {
        self.init(
            path: item.id,
            modifiedAt: item.contentModifiedAt,
            fileSize: item.fileSize,
            pixels: size.pixels
        )
    }

    /// The two hex characters the file is filed under, so one folder never holds ten thousand
    /// entries. The Finder and the file system both prefer two hundred and fifty six of a
    /// hundred to one of twenty-five thousand.
    var shard: String { String(hex.prefix(2)) }

    /// What the memory cache keys on, which wants an object rather than a value.
    var cacheKey: NSString { hex as NSString }
}
