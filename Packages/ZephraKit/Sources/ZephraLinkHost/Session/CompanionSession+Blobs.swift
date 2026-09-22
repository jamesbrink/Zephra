import Foundation
import ZephraLinkProtocol

/// Bytes that do not go in JSON: a reference picture arriving, a thumbnail or a file leaving.
///
/// One blob at a time in each direction. The channel underneath is a single ordered stream, so
/// two overlapping transfers would only be two interleaved orders to keep straight for no gain;
/// a phone sends its picture, then asks for the generation.
extension CompanionSession {
    /// A blob the phone is about to send. Replaces whatever was arriving: a phone that abandons
    /// a transfer half way and starts another is a phone whose first picture nobody wants.
    func begin(_ start: BlobStart) throws {
        guard start.byteCount <= 16_777_216 else {
            throw LinkError(code: .badRequest, reason: "That picture is larger than this link allows.")
        }
        incomingID = start.blobID
        incoming = BlobReassembly(blobID: start.blobID, byteCount: start.byteCount)
    }

    /// One piece of it. A chunk with nothing announced is a broken sender, and a blob that
    /// completes is kept until a request names it.
    func accept(_ chunk: BlobChunk) throws {
        guard incoming != nil, incomingID == chunk.blobID else {
            throw LinkError(code: .badRequest, reason: "That transfer was never announced.")
        }
        guard let whole = try incoming?.accept(chunk) else { return }
        incoming = nil
        incomingID = nil
        blobs[chunk.blobID] = whole
        blobOrder.removeAll { $0 == chunk.blobID }
        blobOrder.append(chunk.blobID)
        // Oldest first, on either bound: a strip of ten pictures must all survive until the
        // request that names them arrives, and ten 16 MiB pictures must not be held because the
        // count alone allowed it.
        while blobOrder.count > Self.blobLimit || heldBlobBytes > Self.blobByteLimit {
            guard !blobOrder.isEmpty else { break }
            blobs.removeValue(forKey: blobOrder.removeFirst())
        }
    }

    /// What the finished blobs come to, which is the other half of the eviction rule.
    var heldBlobBytes: Int { blobs.values.reduce(0) { $0 + $1.count } }

    /// Announces a blob as the answer to one request and sends its bytes behind it.
    ///
    /// The announcement is the reply, so a phone holding the request open sees it close; the
    /// chunks follow under the id it names. Empty data is one empty chunk, never none.
    ///
    /// `from` is the first chunk to send, for a phone asking to carry on rather than to start
    /// again: over the relay a whole file is hundreds of chunks and a clip thousands, so a
    /// transfer a hole stopped at 630 used to cost all 630 again. The announcement still names
    /// the **whole** file's `byteCount`, which is what the phone completes against, and the
    /// bytes are read from the same file either way, so the command stays safe to repeat. A
    /// `from` past the end is a file that has changed underneath the asker, and sends the whole
    /// thing.
    func sendBlob(_ data: Data, mime: String, to request: UUID, from: UInt32 = 0) async throws {
        let start = BlobStart(byteCount: data.count, mime: mime)
        let chunks = BlobChunker.chunks(of: data, blobID: start.blobID)
        try reply(.blob(start), to: request)
        for chunk in chunks.dropFirst(Int(from) < chunks.count ? Int(from) : 0) {
            try await capacity()
            try send(.chunk(chunk))
        }
    }
}
