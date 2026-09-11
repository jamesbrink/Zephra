import Foundation

/// The handshake's first message: the phone says who it is and what it wants.
///
/// Plaintext, because there is no key yet. Everything in it is public — an ephemeral key, a
/// nonce, the device's static keys and its name — and all of it is hashed into the transcript,
/// so a byte changed in flight changes the keys both ends derive and the first tag fails.
public struct Hello: Codable, Hashable, Sendable {
    /// Which protocol the phone speaks.
    public var version: Int
    /// This connection's ephemeral key agreement public key, thirty-two bytes.
    public var ephemeral: Data
    /// The phone's long-lived published keys.
    public var keys: DevicePublicKeys
    /// Sixteen random bytes, so two connections from the same device never share a transcript.
    public var nonce: Data
    /// Whether this is a first connection, offering the secret from a QR code.
    public var pairing: Bool
    /// What the phone is called, for the Mac to show while it asks.
    public var deviceName: String

    /// Creates the opening message.
    public init(
        version: Int = LinkProtocolVersion.current,
        ephemeral: Data,
        keys: DevicePublicKeys,
        nonce: Data,
        pairing: Bool,
        deviceName: String
    ) {
        self.version = version
        self.ephemeral = ephemeral
        self.keys = keys
        self.nonce = nonce
        self.pairing = pairing
        self.deviceName = deviceName
    }
}
