import CryptoKit
import Foundation

/// The thumbnails the Mac has sent, kept as the JPEG bytes that arrived.
///
/// The digest is the Mac's own cache rule, moved one device along: `ThumbnailKey` on the Mac
/// names a baked thumbnail by the file, the state that file was in and the size it was baked
/// at, precisely so a picture that changed misses rather than showing yesterday's pixels under
/// today's name. The phone has the same problem and the same three facts — the name, the
/// modification time the entry carries, and the pixels asked for — so it uses the same rule.
///
/// Sharded two characters deep for the reason the Mac shards: one folder of ten thousand files
/// is slower to open than two hundred and fifty six folders of forty.
///
/// The bytes are written exactly as received. Re-encoding a JPEG to store it would cost a
/// decode and an encode per picture to make the file slightly worse.
actor ThumbnailStore {
    /// The two sizes the phone ever asks for: a cell in the three-across grid, and the viewer
    /// before the whole file has come down. Two rather than the Mac's four, because a phone
    /// has one grid at one width.
    static let cellPixels = 256
    static let viewerPixels = 512

    /// Where the files are, or nil for a store that keeps nothing.
    private let directory: URL?

    /// A store under one library root.
    init(root: URL?) {
        directory = root?.appending(path: "Thumbnails", directoryHint: .isDirectory)
        if let directory { try? CacheDirectories.prepare(directory) }
    }

    /// The thumbnail already held for one picture at one size, or nil.
    func data(for entry: CachedEntry, pixels: Int) -> Data? {
        guard let url = url(for: entry, pixels: pixels) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Keeps one thumbnail, as it arrived.
    func store(_ data: Data, for entry: CachedEntry, pixels: Int) {
        guard let url = url(for: entry, pixels: pixels) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Empties the folder.
    func clear() {
        guard let directory else { return }
        CacheDirectories.empty(directory)
    }

    /// How many bytes the thumbnails occupy.
    func size() -> Int64 {
        directory.map(CacheDirectories.size(of:)) ?? 0
    }

    /// Where one thumbnail lives: two characters of shard, then the digest.
    private func url(for entry: CachedEntry, pixels: Int) -> URL? {
        guard let directory else { return nil }
        let digest = Self.digest(
            fileName: entry.hostID == nil ? entry.fileName : entry.fileName + ":" + entry.version, contentModifiedAt: entry.contentModifiedAt, pixels: pixels)
        return directory
            .appending(path: String(digest.prefix(2)), directoryHint: .isDirectory)
            .appending(path: "\(digest).jpg")
    }

    /// What one thumbnail is filed under: the first sixteen bytes of the SHA-256 of the file's
    /// name, the time it last changed and the pixels it was asked for, as hex.
    ///
    /// Truncated for the reason `LibraryEntry.version` is truncated: this is a cache key, not a
    /// security claim, and a short name is a short path to open.
    static func digest(fileName: String, contentModifiedAt: Date, pixels: Int) -> String {
        let stamp = stamps.format(contentModifiedAt)
        let material = "\(fileName)\n\(stamp)\n\(pixels)"
        return SHA256.hash(data: Data(material.utf8))
            .prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// One spelling of a date, so the same picture digests the same on every launch. The same
    /// style `LibraryEntry` fingerprints with, fractional seconds included.
    private static let stamps = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
