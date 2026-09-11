import Foundation

/// What a command came back with, in the envelope whose `inReplyTo` names it.
///
/// Every command gets exactly one of these, a refusal included, so the phone can hold a request
/// open and know it will close. A blob reply is the announcement only: the bytes follow as
/// chunk frames under the id it names.
public enum Reply: Hashable, Sendable {
    /// It was done, and there is nothing to say about it.
    case ok
    /// The press of Generate was queued, under this run id.
    case queued(batchID: UUID)
    /// The bytes asked for are about to follow as chunks.
    case blob(BlobStart)
    /// The window onto the library that was asked for.
    case entries(LibraryPage)
    /// It was refused.
    case error(LinkError)
}
