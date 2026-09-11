import ZephraLinkProtocol

/// Why a relay road failed.
///
/// `refused` carries the relay's own words, not ours. The reasons are the deployed Lambda's
/// (`bad room`, `challenge expired`, `room does not match key`, `not allowed`, `no host`,
/// `room busy`) and rewriting them here would give one failure two names, one of which would go
/// stale.
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

/// What the relay's three refusals of a guest mean to the phone.
///
/// Two of them are about the moment — the Mac is not in its room yet, or its one guest slot is
/// taken — and are worth another attempt after a wait. The third is about this device, and no
/// number of attempts will change it, so it is a sentence for a person rather than a retry.
extension RelayError {
    /// The relay's own word for a guest whose key is not on the host's allow-list.
    public static let notAllowed = "not allowed"
    /// The relay's own words for the refusals a later attempt could get past.
    public static let temporaryReasons: Set<String> = ["no host", "room busy"]

    /// Whether waiting and trying again is worth doing.
    public var isTemporary: Bool {
        guard case .refused(let reason) = self else { return false }
        return Self.temporaryReasons.contains(reason)
    }

    /// The refusal a person is owed, when this one is about their device rather than the moment.
    public var refusalToShow: LinkError? {
        guard case .refused(let reason) = self, reason == Self.notAllowed else { return nil }
        return LinkError.notPaired
    }
}
