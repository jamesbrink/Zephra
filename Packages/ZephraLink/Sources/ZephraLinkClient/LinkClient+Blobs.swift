import Foundation
import ZephraLinkProtocol

/// The bytes that do not fit in JSON: thumbnails and files coming in, a reference picture
/// going out.
extension LinkClient {
    /// A blob the Mac has said is coming, which is the only kind whose chunks are kept.
    ///
    /// Opened here, where the announcement is read, rather than where the request that asked for
    /// it resumes: the reply and the first chunk are two frames on one stream, and a phone that
    /// had not got back to its own `await` would otherwise drop the second. An announcement no
    /// request asked for is still an announcement; what is refused is a chunk for a blob nothing
    /// announced at all, which before this opened a transfer of whatever size it liked.
    /// `wanted` is the answer to a request this phone made, and is **not** in `blobLimit`'s count:
    /// the limit bounds what a Mac can make this phone hold unasked, and a grid announcing five
    /// thumbnails used to evict the forty-megabyte clip somebody was waiting on.
    ///
    /// `resuming` is what an earlier attempt at the same file got to, where this announcement is
    /// the answer to a request that asked to carry on. The file is the same file and its
    /// `byteCount` is the whole of it either way; only the chunks are a tail.
    func announce(_ start: BlobStart, wanted: Bool = false, resuming: BlobResumption? = nil) {
        guard let byteCount = Int(exactly: start.byteCount),
              blobBudget.reserve(owner: transferOwner, blob: start.blobID, bytes: byteCount) else {
            fail(start.blobID, with: LinkClientError.tooManyTransfers)
            return
        }
        if let resuming, resuming.byteCount == start.byteCount {
            blobs[start.blobID] = BlobReassembly(
                blobID: start.blobID, byteCount: start.byteCount, resuming: resuming.bytes,
                from: resuming.nextIndex)
        } else {
            blobs[start.blobID] = BlobReassembly(blobID: start.blobID, byteCount: start.byteCount)
        }
        timers[start.blobID] = expire(start.blobID, after: LinkClient.blobIdleTimeout)
        guard !wanted else {
            // Remembered rather than inferred later: this is the one moment that knows the
            // transfer was asked for, and it is what says whose partial is worth keeping.
            wantedBlobs.insert(start.blobID)
            return
        }
        blobOrder.removeAll { $0 == start.blobID }
        blobOrder.append(start.blobID)
        while blobOrder.count > LinkClient.blobLimit {
            fail(blobOrder.removeFirst(), with: LinkClientError.tooManyTransfers)
        }
    }

    /// One chunk, in order, of a blob that was announced.
    ///
    /// A chunk for anything else is dropped with a line in the log: the announcement is what
    /// says how much memory this transfer may take, so there is nothing to assemble it into.
    ///
    /// A chunk out of its turn, or one whose transfer changed length part way through, is what a
    /// hole in the stream leaves behind: the frame before it is gone, the run is broken, and this
    /// transfer is over. It fails as `LinkClientError.lost`, which the caller asks again — and it
    /// is **this** transfer alone, which is the whole point of not settling everything on a gap.
    /// Anything else `accept` refuses is a sender that is misbehaving rather than a road that
    /// dropped something, and keeps its refusal: a transfer larger than it announced most of all.
    func receive(_ chunk: BlobChunk) {
        guard var assembly = blobs[chunk.blobID] else {
            return logger.notice("A chunk arrived for a transfer the Mac never announced.")
        }
        // An index of 0 is not out of turn however far in the transfer is: it is a sender that
        // was asked for a tail and is sending the whole file, or a duplicate first chunk, and
        // `accept` is the one place that tells those two apart.
        guard
            chunk.index == 0
                || (chunk.index == assembly.nextIndex
                    && (assembly.chunkCount ?? chunk.count) == chunk.count)
        else {
            logger.notice("A hole in the stream cost a transfer its bytes; the caller asks again.")
            return fail(chunk.blobID, with: LinkClientError.lost)
        }
        do {
            guard let whole = try assembly.accept(chunk) else {
                blobs[chunk.blobID] = assembly
                // The clock is idle time: every chunk that lands buys the transfer another
                // fifteen seconds, so a clip that is crossing slowly is not given up on and a
                // transfer that stopped is.
                timers.removeValue(forKey: chunk.blobID)?.cancel()
                timers[chunk.blobID] = expire(chunk.blobID, after: LinkClient.blobIdleTimeout)
                return
            }
            finish(chunk.blobID, with: whole)
        } catch {
            fail(chunk.blobID, with: error)
        }
    }

    /// The whole of one blob, waiting for it if it has not all arrived.
    ///
    /// A transfer nothing is assembling any more is `lost` at once rather than waited out: a gap
    /// throws away everything in flight, and a caller that reached its `await` a moment later
    /// would otherwise sit on a continuation nobody can resume until the blob timeout.
    func blob(_ id: UUID) async throws -> Data {
        if let whole = arrivedBlobs.removeValue(forKey: id) {
            blobBudget.release(owner: transferOwner, blob: id)
            timers.removeValue(forKey: id)?.cancel()
            blobOrder.removeAll { $0 == id }
            return whole
        }
        guard blobs[id] != nil else { throw LinkClientError.lost }
        return try await withCheckedThrowingContinuation { continuation in
            blobWaiters[id] = continuation
            // The clock started at the announcement and is re-armed by the chunks themselves; a
            // second one here would move the deadline every time somebody asked.
            if timers[id] == nil { timers[id] = expire(id, after: LinkClient.blobIdleTimeout) }
        }
    }

    /// One blob out: the announcement, then the bytes as chunks.
    ///
    /// The announcement first for the reason the Mac sends one: the far end can refuse a blob
    /// it does not want before any of it is read.
    func sendBlob(_ bytes: Data, mime: String) async throws -> UUID {
        guard bytes.count <= 16_777_216 else { throw LinkClientError.tooManyTransfers }
        try await transferAdmission.enter(transferOwner, priority: .reference)
        defer { transferAdmission.leave(transferOwner) }
        guard let owner = session else { throw LinkClientError.notConnected }
        let start = BlobStart(byteCount: bytes.count, mime: mime)
        try send(.envelope(try Envelope.encoding(start, kind: .blobStart)))
        for chunk in BlobChunker.chunks(of: bytes, blobID: start.blobID) {
            try await owner.capacity()
            guard session === owner else { throw LinkClientError.notConnected }
            try send(.chunk(chunk))
        }
        return start.blobID
    }

    /// One blob that arrived whole, handed to whoever asked or kept until somebody does.
    private func finish(_ id: UUID, with whole: Data) {
        blobs[id] = nil
        blobOrder.removeAll { $0 == id }
        wantedBlobs.remove(id)
        timers.removeValue(forKey: id)?.cancel()
        if let waiter = blobWaiters.removeValue(forKey: id) {
            blobBudget.release(owner: transferOwner, blob: id)
            waiter.resume(returning: whole)
        } else {
            arrivedBlobs[id] = whole
            blobOrder.append(id)
            timers[id] = expire(id, after: LinkClient.blobIdleTimeout)
            while blobOrder.count > LinkClient.blobLimit {
                fail(blobOrder.removeFirst(), with: LinkClientError.tooManyTransfers)
            }
        }
    }
}
