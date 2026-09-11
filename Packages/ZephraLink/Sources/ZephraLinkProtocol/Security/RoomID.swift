import CryptoKit
import Foundation

/// Where two devices meet on the relay: the first sixteen bytes of the SHA-256 of a Mac's
/// signing key, as lowercase hex.
///
/// Derived rather than assigned, so the relay hands out no names and stores no mapping: a phone
/// that has paired with a Mac already knows the Mac's public key and can work out where to
/// knock. Sixteen bytes because the room is a rendezvous point and not a secret — joining one
/// still takes a signature over the server's challenge.
public struct RoomID: RawRepresentable, Codable, Hashable, Sendable {
    /// The hex, lowercase, thirty-two characters.
    public let rawValue: String

    /// Takes a room name as it stands, for reading one back off the wire.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The room a signing public key names.
    public init(signingPublicKey: Data) {
        let digest = SHA256.hash(data: signingPublicKey)
        rawValue = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
