import Foundation
import ZephraLinkProtocol

/// What survived of a transfer that stopped part way, so the next attempt asks for the rest.
///
/// Over the relay a whole picture is ninety-odd chunks and a clip two and a half thousand, and
/// one lost frame costs the transfer it was in. Starting again from chunk zero every time meant a
/// 40 MB clip on a road that loses a frame every few hundred never finished at all: each attempt
/// got further only by luck. This is the two facts the next attempt needs — the bytes in hand and
/// the index they stop at — and one it checks them against.
///
/// The blob's id is deliberately not in it. The next attempt is a new request with a new answer
/// and a new blob id; what carries over is the file's bytes, never the transfer's identity.
struct BlobResumption: Sendable {
    /// The bytes that did arrive, in order and with no gaps in them.
    var budgetID: UUID?
    let bytes: Data
    /// The chunk index the next one has to carry.
    let nextIndex: UInt32
    /// How long the file was said to be when this much of it arrived. A different answer next
    /// time is a different file, and the resumption is dropped rather than spliced onto it.
    let byteCount: Int

    /// What one transfer got to, or nil where it got nowhere worth carrying over — a single chunk
    /// is cheaper to ask for again than to reason about.
    init?(_ assembly: BlobReassembly) {
        guard assembly.nextIndex > 0 else { return nil }
        bytes = assembly.partial
        nextIndex = assembly.nextIndex
        byteCount = assembly.byteCount
    }
}
