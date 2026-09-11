import Foundation

/// The announcement that a blob is about to arrive as chunks: a thumbnail, a file, a clip.
///
/// Sent as its own envelope rather than as a header on the first chunk, so the receiver can
/// refuse a blob it does not want — too large, or a mime it cannot show — before any of it is
/// read.
public struct BlobStart: Codable, Hashable, Sendable {
    /// The blob's identity, which every one of its chunks repeats.
    public let blobID: UUID
    /// How many bytes to expect in all.
    public let byteCount: Int
    /// What the bytes are: "image/png", "video/mp4", "image/jpeg".
    public let mime: String

    /// Announces a blob.
    public init(blobID: UUID = UUID(), byteCount: Int, mime: String) {
        self.blobID = blobID
        self.byteCount = byteCount
        self.mime = mime
    }
}
