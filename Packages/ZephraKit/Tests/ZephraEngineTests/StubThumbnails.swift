import Foundation
import ZephraLinkHost

/// Thumbnails without Image I/O: the same two bytes for every picture, and nothing for a file
/// that is not there.
///
/// What the suites check is that the bytes asked for are the bytes that arrive and that the file
/// asked about was the right one; baking a real JPEG would only be testing Image I/O.
final class StubThumbnails: ThumbnailSupply, @unchecked Sendable {
    /// The bytes every thumbnail is.
    static let bytes = Data([0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43])

    private let lock = NSLock()
    private var asked: [URL] = []

    /// Every picture a thumbnail has been asked for, in order.
    var requests: [URL] { lock.withLock { asked } }

    func thumbnail(for url: URL, pixels: Int) async -> Data? {
        lock.withLock { asked.append(url) }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return Self.bytes
    }
}
