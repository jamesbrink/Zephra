import Foundation

/// One piece of a blob, framed as bytes rather than as JSON.
///
/// Base64 inside an envelope would cost a third more on the wire for every thumbnail and every
/// clip, which is the whole of what a phone session moves. So a chunk is its own frame kind
/// with a fixed 24-byte header and the payload raw behind it.
public struct BlobChunk: Hashable, Sendable {
    /// Which blob this belongs to.
    public let blobID: UUID
    /// Where it goes, counting from zero.
    public let index: UInt32
    /// How many chunks the blob has in all.
    public let count: UInt32
    /// The bytes themselves.
    public let bytes: Data

    /// Creates one chunk.
    public init(blobID: UUID, index: UInt32, count: UInt32, bytes: Data) {
        self.blobID = blobID
        self.index = index
        self.count = count
        self.bytes = bytes
    }

    /// Whether this is the chunk the blob ends on.
    public var isLast: Bool { index + 1 == count }
}
