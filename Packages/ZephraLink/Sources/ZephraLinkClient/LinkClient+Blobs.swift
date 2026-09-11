import Foundation
import ZephraLinkProtocol

/// The bytes that do not fit in JSON: thumbnails and files coming in, a reference picture
/// going out.
extension LinkClient {
    /// A command whose answer is bytes: the reply announces the blob and the chunks follow.
    public func fetchBlob(_ command: Command) async throws -> Data {
        guard !isFrozen else { throw LinkClientError.notConnected }
        switch try await request(command) {
        case .blob(let start): return try await blob(start.blobID)
        case .error(let error): throw error
        case .ok, .queued, .entries: throw LinkClientError.unexpectedReply
        }
    }

    /// One chunk, in order, of whichever blob it belongs to.
    ///
    /// A chunk for a blob nothing announced still opens a transfer: the reply that names it and
    /// the first chunk behind it are two frames on one stream, and a phone that had not yet
    /// looked at the first would otherwise drop the second.
    func receive(_ chunk: BlobChunk) {
        var assembly = blobs[chunk.blobID] ?? BlobReassembly(blobID: chunk.blobID)
        do {
            guard let whole = try assembly.accept(chunk) else {
                blobs[chunk.blobID] = assembly
                return
            }
            blobs[chunk.blobID] = nil
            timers.removeValue(forKey: chunk.blobID)?.cancel()
            if let waiter = blobWaiters.removeValue(forKey: chunk.blobID) {
                waiter.resume(returning: whole)
            } else {
                arrivedBlobs[chunk.blobID] = whole
            }
        } catch {
            fail(chunk.blobID, with: error)
        }
    }

    /// The whole of one blob, waiting for it if it has not all arrived.
    func blob(_ id: UUID) async throws -> Data {
        if let whole = arrivedBlobs.removeValue(forKey: id) { return whole }
        return try await withCheckedThrowingContinuation { continuation in
            blobWaiters[id] = continuation
            timers[id] = expire(id, after: LinkClient.blobTimeout)
        }
    }

    /// One blob out: the announcement, then the bytes as chunks.
    ///
    /// The announcement first for the reason the Mac sends one: the far end can refuse a blob
    /// it does not want before any of it is read.
    func sendBlob(_ bytes: Data, mime: String) throws -> UUID {
        let start = BlobStart(byteCount: bytes.count, mime: mime)
        try send(.envelope(try Envelope.encoding(start, kind: .blobStart)))
        for chunk in BlobChunker.chunks(of: bytes, blobID: start.blobID) {
            try send(.chunk(chunk))
        }
        return start.blobID
    }
}
