import CryptoKit
import Foundation

/// What one end of the link publishes about itself: two thirty-two byte Curve25519 keys.
///
/// Two keys rather than one, because the two jobs are different and sharing a key between them
/// is how signature schemes get broken. The agreement key is half of every shared secret in the
/// handshake; the signing key is what proves to the relay that a device may join a room, and
/// its hash is the room's name.
public struct DevicePublicKeys: Codable, Hashable, Sendable {
    /// The Curve25519 key agreement public key, thirty-two bytes.
    public let keyAgreement: Data
    /// The Curve25519 signing public key, thirty-two bytes.
    public let signing: Data

    /// Takes a pair of published keys.
    public init(keyAgreement: Data, signing: Data) {
        self.keyAgreement = keyAgreement
        self.signing = signing
    }

    /// The relay room this device's Mac is reachable in.
    public var roomID: RoomID { RoomID(signingPublicKey: signing) }

    /// The agreement key as CryptoKit's own type, or nil when the bytes are not a key.
    public func agreementKey() throws -> Curve25519.KeyAgreement.PublicKey {
        try Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyAgreement)
    }

    /// The signing key as CryptoKit's own type, or nil when the bytes are not a key.
    public func signingKey() throws -> Curve25519.Signing.PublicKey {
        try Curve25519.Signing.PublicKey(rawRepresentation: signing)
    }
}

/// One letter per key on the wire.
///
/// These two keys are in every `Hello` and in every QR payload, and the payload is measured in
/// the modules of a code somebody photographs. The names are above, where they are read.
extension DevicePublicKeys {
    enum CodingKeys: String, CodingKey {
        case keyAgreement = "a"
        case signing = "s"
    }
}
