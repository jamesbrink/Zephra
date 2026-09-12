import Foundation

/// A transfer a hole stopped, thrown so the attempt above it can ask for the rest.
///
/// It carries the reason as well as the resumption because the attempt that catches it is the one
/// that gives up after `blobAttempts`, and what it gives up with should be what actually went
/// wrong — `lost` for a hole, `timedOut` for a Mac that stopped sending.
struct BlobInterrupted: Error {
    /// Why this attempt stopped, which is what the caller sees if there are none left.
    let reason: LinkClientError
    /// What survived of it, or nil where nothing worth carrying over did.
    let resumption: BlobResumption?
}
