import Foundation

/// Cutting a blob into the chunks that carry it.
///
/// 64 KiB because the relay's frames are capped at 128 KB: one chunk plus its header and the
/// channel's tag fits inside that with room to spare, and a chunk that has to be split again
/// by the transport would put the reassembly rules in two places.
public enum BlobChunker {
    /// The largest payload one chunk carries.
    public static let chunkSize = 64 * 1024

    /// `data` cut into chunks, all of them `chunkSize` but the last.
    ///
    /// Empty data is one empty chunk, not none: a blob of nothing still has to be announced,
    /// sent and completed, and a zero-chunk blob would have no frame to complete it on.
    public static func chunks(of data: Data, blobID: UUID = UUID()) -> [BlobChunk] {
        guard !data.isEmpty else {
            return [BlobChunk(blobID: blobID, index: 0, count: 1, bytes: Data())]
        }
        let count = (data.count + chunkSize - 1) / chunkSize
        return (0..<count).map { index in
            let start = data.startIndex + index * chunkSize
            let end = min(start + chunkSize, data.endIndex)
            return BlobChunk(
                blobID: blobID, index: UInt32(index), count: UInt32(count),
                bytes: Data(data[start..<end]))
        }
    }
}
