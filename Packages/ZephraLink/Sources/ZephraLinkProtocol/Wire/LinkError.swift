/// A refusal, in the one shape that crosses the wire.
///
/// `Codable` because it is also the body of a `MessageKind.error` envelope and the payload of
/// `Reply.error`: a failure travels as data, not as a Swift error, so the phone renders the
/// same words whatever raised it.
public struct LinkError: Error, Codable, Hashable, Sendable {
    /// What kind of refusal this is.
    public let code: LinkErrorCode
    /// What to tell the person, in a sentence.
    public let reason: String

    /// Creates a refusal.
    public init(code: LinkErrorCode, reason: String) {
        self.code = code
        self.reason = reason
    }

    /// The one answer to a device this Mac will not talk to, whichever way it asked.
    ///
    /// One sentence and one code on purpose: it is sent before anything is authenticated, so
    /// every word in it is a word anyone who can reach the port can read. It names no Mac, no
    /// model and no person, and it does not say whether a code happens to be on screen — two
    /// answers here were two oracles. See `HandshakeResponder`.
    public static let notPaired = LinkError(
        code: .notPaired, reason: "This Mac has not paired this phone.")
    /// A request this Mac will not answer, from a device it has already let in.
    public static let refused = LinkError(
        code: .refused, reason: "This Mac is not accepting a new device right now.")
    /// The two ends speak different versions of the protocol.
    public static let protocolMismatch = LinkError(
        code: .protocolMismatch,
        reason: "This Mac and this device are running versions of Zephra that cannot talk to each other.")
}
