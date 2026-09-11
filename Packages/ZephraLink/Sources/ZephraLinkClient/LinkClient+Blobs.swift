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

    /// A blob the Mac has said is coming, which is the only kind whose chunks are kept.
    ///
    /// Opened here, where the announcement is read, rather than where the request that asked for
    /// it resumes: the reply and the first chunk are two frames on one stream, and a phone that
    /// had not got back to its own `await` would otherwise drop the second. An announcement no
    /// request asked for is still an announcement; what is refused is a chunk for a blob nothing
    /// announced at all, which before this opened a transfer of whatever size it liked.
    func announce(_ start: BlobStart) {
        blobs[start.blobID] = BlobReassembly(blobID: start.blobID, byteCount: start.byteCount)
        blobOrder.removeAll { $0 == start.blobID }
        blobOrder.append(start.blobID)
        timers[start.blobID] = expire(start.blobID, after: LinkClient.blobTimeout)
        while blobOrder.count > LinkClient.blobLimit {
            fail(blobOrder.removeFirst(), with: LinkClientError.tooManyTransfers)
        }
    }

    /// One chunk, in order, of a blob that was announced.
    ///
    /// A chunk for anything else is dropped with a line in the log: the announcement is what
    /// says how much memory this transfer may take, so there is nothing to assemble it into.
    func receive(_ chunk: BlobChunk) {
        guard var assembly = blobs[chunk.blobID] else {
            return logger.notice("A chunk arrived for a transfer the Mac never announced.")
        }
        do {
            guard let whole = try assembly.accept(chunk) else {
                blobs[chunk.blobID] = assembly
                return
            }
            finish(chunk.blobID, with: whole)
        } catch {
            fail(chunk.blobID, with: error)
        }
    }

    /// The whole of one blob, waiting for it if it has not all arrived.
    func blob(_ id: UUID) async throws -> Data {
        if let whole = arrivedBlobs.removeValue(forKey: id) { return whole }
        return try await withCheckedThrowingContinuation { continuation in
            blobWaiters[id] = continuation
            // The clock started at the announcement; a second one here would move the deadline
            // every time somebody asked.
            if timers[id] == nil { timers[id] = expire(id, after: LinkClient.blobTimeout) }
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

    /// One blob that arrived whole, handed to whoever asked or kept until somebody does.
    private func finish(_ id: UUID, with whole: Data) {
        blobs[id] = nil
        blobOrder.removeAll { $0 == id }
        timers.removeValue(forKey: id)?.cancel()
        if let waiter = blobWaiters.removeValue(forKey: id) {
            waiter.resume(returning: whole)
        } else {
            arrivedBlobs[id] = whole
        }
    }
}
