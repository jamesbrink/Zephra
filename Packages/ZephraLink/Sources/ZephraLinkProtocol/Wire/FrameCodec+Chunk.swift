import Foundation

/// A chunk's own framing: a fixed header and the payload raw behind it.
extension FrameCodec {
    /// The header and the bytes.
    static func encode(_ chunk: BlobChunk) -> Data {
        var data = Data(capacity: chunkHeaderSize + chunk.bytes.count)
        withUnsafeBytes(of: chunk.blobID.uuid) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunk.index.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunk.count.bigEndian) { data.append(contentsOf: $0) }
        data.append(chunk.bytes)
        return data
    }

    /// The chunk those bytes are.
    ///
    /// The header is read unaligned out of the buffer rather than through an array copy: a
    /// chunk is 64 KiB and this runs once per chunk for every thumbnail and every clip.
    static func decodeChunk(_ body: Data) throws -> BlobChunk {
        guard body.count >= chunkHeaderSize else {
            throw LinkError(code: .badRequest, reason: "A chunk arrived without a complete header.")
        }
        let header: (id: UUID, index: UInt32, count: UInt32) = body.withUnsafeBytes { raw in
            (
                UUID(uuid: raw.loadUnaligned(as: uuid_t.self)),
                UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: 16, as: UInt32.self)),
                UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
            )
        }
        guard header.count > 0, header.index < header.count else {
            throw LinkError(code: .badRequest, reason: "A chunk claims a place outside its transfer.")
        }
        return BlobChunk(
            blobID: header.id, index: header.index, count: header.count,
            bytes: Data(body.dropFirst(chunkHeaderSize)))
    }
}
