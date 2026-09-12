import Foundation

/// Putting one blob back together as its chunks arrive.
///
/// In order only. The channel underneath is a single ordered stream, so a gap means loss or
/// tampering rather than overtaking, and accepting an out-of-order chunk would mean holding
/// arbitrary memory for a sender that never sends the missing one. A duplicate index is the
/// same answer for the same reason.
///
/// And no longer than it said it would be. The announcement carries a `byteCount`, which is what
/// the far end decided to accept the transfer on; without holding the sender to it, a blob
/// announced as a thumbnail could arrive as sixty-four megabytes, and the announcement would be
/// a courtesy rather than a limit.
public struct BlobReassembly: Sendable {
    /// The most any one blob may occupy while it is being assembled.
    public static let byteCap = 64 * 1024 * 1024

    /// The blob being assembled.
    public let blobID: UUID
    /// How many bytes it was announced as, never more than `byteCap`.
    public let byteCount: Int
    private var bytes = Data()
    private var next: UInt32 = 0
    private var total: UInt32?
    /// The index this transfer was resumed at, or zero. Read once, to tell a sender that started
    /// over from a chunk that arrived twice.
    private var resumedFrom: UInt32 = 0

    /// The index the next chunk has to carry. A receiver reads it to tell the one thing a hole in
    /// the stream looks like here — a chunk out of its turn — apart from a sender that is
    /// misbehaving, which is the difference between failing this transfer and refusing it.
    public var nextIndex: UInt32 { next }

    /// How many chunks this transfer said it has, once a chunk has said. Read for the same
    /// reason as `nextIndex`.
    public var chunkCount: UInt32? { total }

    /// What of the blob has arrived so far, which is what a transfer a hole stopped hands to the
    /// attempt that carries on from where it got to.
    public var partial: Data { bytes }

    /// Starts assembling the blob with this id, of the length its announcement claimed.
    ///
    /// The claim is trimmed to `byteCap` rather than refused, so a sender that announces more
    /// than this link carries fails on the chunk that passes the cap, with the same words as any
    /// other over-long transfer.
    public init(blobID: UUID, byteCount: Int) {
        self.blobID = blobID
        self.byteCount = min(max(byteCount, 0), Self.byteCap)
    }

    /// Starts assembling a blob that is already part way through: `resuming` is what an earlier
    /// attempt at the same file got, and `from` is the index the next chunk should carry.
    ///
    /// The new blob has an id of its own — it is a fresh answer to a fresh request — so what is
    /// carried over is the bytes and the place, never the identity. Two things start it fresh
    /// instead: a resumption longer than the blob now claims to be, and a chunk that arrives at
    /// index 0, which is a sender that ignored the ask and is sending the whole file. The chunk
    /// count follows the byte count, so a transfer whose length moved is a transfer whose count
    /// moved, and the first of those two rules covers both.
    public init(blobID: UUID, byteCount: Int, resuming: Data, from index: UInt32) {
        self.init(blobID: blobID, byteCount: byteCount)
        guard index > 0, resuming.count <= self.byteCount else { return }
        bytes = resuming
        next = index
        resumedFrom = index
    }

    /// Takes one chunk, and answers the whole blob when that chunk was the last.
    ///
    /// Throws rather than ignoring: a chunk that does not fit is a broken sender or a tampered
    /// stream, and either way the transfer is over.
    public mutating func accept(_ chunk: BlobChunk) throws -> Data? {
        guard chunk.blobID == blobID else {
            throw LinkError(code: .badRequest, reason: "That chunk belongs to a different transfer.")
        }
        // A sender that was asked for a tail and started at the beginning anyway — an older Mac
        // that does not know `fromChunk` — is answered by forgetting what was resumed, not by
        // refusing every chunk it sends. Only before this transfer has taken a chunk of its own:
        // after that an index of 0 is a duplicate, which is what it has always been.
        if chunk.index == 0, next > 0, next == resumedFrom {
            bytes = Data()
            next = 0
            total = nil
        }
        guard chunk.index == next else {
            throw LinkError(code: .badRequest, reason: "A chunk arrived out of order.")
        }
        if let total, total != chunk.count {
            throw LinkError(code: .badRequest, reason: "The transfer changed length part way through.")
        }
        guard bytes.count + chunk.bytes.count <= byteCount else {
            throw LinkError(code: .badRequest, reason: "That transfer is larger than it announced.")
        }
        total = chunk.count
        bytes.append(chunk.bytes)
        next += 1
        guard next == chunk.count else { return nil }
        guard bytes.count == byteCount else {
            throw LinkError(code: .badRequest, reason: "That transfer is shorter than it announced.")
        }
        return bytes
    }
}
