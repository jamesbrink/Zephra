import ZephraLinkProtocol

/// Why a relay road failed.
///
/// `refused` carries the relay's own words, not ours. The reasons are the deployed Lambda's
/// (`bad room`, `challenge expired`, `room does not match key`) and rewriting them here would
/// give one failure two names, one of which would go stale.
public enum RelayError: Error, Hashable, Sendable {
    /// The relay would not let this device in, for the reason it gave.
    case refused(String)
    /// The relay said something out of turn: a `joined` before a challenge, a `send` before a
    /// join. The connection is not the one the protocol describes, so it is not used.
    case unexpected(RelayMessage.Action)
    /// The socket closed before the join finished.
    case closed
    /// A message arrived that is not a relay message at all.
    case malformed
}
