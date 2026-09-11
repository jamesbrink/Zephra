import CryptoKit
import Foundation

/// Proving a device may join a room.
///
/// The signature is over the relay's own challenge, the room and the role, so it is good for
/// one join of one room against one nonce and cannot be replayed into another. The relay
/// verifies it against the public key in the same message and checks that the key hashes to the
/// room — for a host only. A guest signs with its own key and is let in, because the host will
/// refuse an unknown static in the handshake the relay cannot read.
public enum RelayJoin {
    /// How many bytes the relay's challenge is.
    public static let nonceByteCount = 32
    /// How long a challenge is good for, and it is single-use.
    public static let challengeLifetime: TimeInterval = 60

    /// The bytes both ends sign and verify: the nonce raw, then the room and the role as ASCII,
    /// with nothing between them.
    ///
    /// No separators and no length prefixes, because none of the three can run into the next:
    /// the nonce is a fixed thirty-two bytes and the room a fixed thirty-two hex characters, so
    /// the role is whatever is left. A host's message is 68 bytes and a guest's 69.
    public static func message(nonce: Data, room: RoomID, role: RelayRole) -> Data {
        nonce + Data(room.rawValue.utf8) + Data(role.rawValue.utf8)
    }

    /// A device's signature over one challenge.
    public static func sign(
        identity: DeviceIdentity, nonce: Data, room: RoomID, role: RelayRole
    ) throws -> Data {
        try identity.signing.signature(for: message(nonce: nonce, room: room, role: role))
    }

    /// Whether that signature is good.
    public static func verify(
        publicKey: Data, nonce: Data, room: RoomID, role: RelayRole, signature: Data
    ) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(
            signature, for: message(nonce: nonce, room: room, role: role))
    }

    /// The join message a device sends, signed.
    public static func message(
        identity: DeviceIdentity, nonce: Data, room: RoomID, role: RelayRole
    ) throws -> RelayMessage {
        .join(
            room: room,
            publicKey: identity.publicKeys.signing,
            role: role,
            signature: try sign(identity: identity, nonce: nonce, room: room, role: role))
    }
}
