/// What the other end of the room just did.
///
/// The relay tells each side when the other arrives or goes, so a phone knows the Mac is asleep
/// without waiting for a request to time out.
public enum RelayPeerEvent: String, Codable, Hashable, Sendable, CaseIterable {
    /// The other end joined.
    case joined
    /// The other end went.
    case left
}
