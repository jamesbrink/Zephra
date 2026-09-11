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

    /// The device is not paired with this Mac.
    public static let notPaired = LinkError(
        code: .notPaired, reason: "This device is not paired with this Mac.")
    /// No pairing is open, so a request to pair cannot be answered.
    public static let refused = LinkError(
        code: .refused, reason: "This Mac is not accepting a new device right now.")
    /// The two ends speak different versions of the protocol.
    public static let protocolMismatch = LinkError(
        code: .protocolMismatch,
        reason: "This Mac and this device are running versions of Zephra that cannot talk to each other.")
}
