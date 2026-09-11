import Foundation

/// Putting one blob back together as its chunks arrive.
///
/// In order only. The channel underneath is a single ordered stream, so a gap means loss or
/// tampering rather than overtaking, and accepting an out-of-order chunk would mean holding
/// arbitrary memory for a sender that never sends the missing one. A duplicate index is the
/// same answer for the same reason.
public struct BlobReassembly: Sendable {
    /// The most any one blob may occupy while it is being assembled.
    public static let byteCap = 64 * 1024 * 1024

    /// The blob being assembled.
    public let blobID: UUID
    private var bytes = Data()
    private var next: UInt32 = 0
    private var total: UInt32?

    /// Starts assembling the blob with this id.
    public init(blobID: UUID) {
        self.blobID = blobID
    }

    /// Takes one chunk, and answers the whole blob when that chunk was the last.
    ///
    /// Throws rather than ignoring: a chunk that does not fit is a broken sender or a tampered
    /// stream, and either way the transfer is over.
    public mutating func accept(_ chunk: BlobChunk) throws -> Data? {
        guard chunk.blobID == blobID else {
            throw LinkError(code: .badRequest, reason: "That chunk belongs to a different transfer.")
        }
        guard chunk.index == next else {
            throw LinkError(code: .badRequest, reason: "A chunk arrived out of order.")
        }
        if let total, total != chunk.count {
            throw LinkError(code: .badRequest, reason: "The transfer changed length part way through.")
        }
        guard bytes.count + chunk.bytes.count <= Self.byteCap else {
            throw LinkError(code: .badRequest, reason: "That transfer is larger than this link allows.")
        }
        total = chunk.count
        bytes.append(chunk.bytes)
        next += 1
        return next == chunk.count ? bytes : nil
    }
}
