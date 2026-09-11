import CryptoKit
import Foundation

/// Proving a device may join a room.
///
/// The signature is over the relay's own challenge, the room and the role, so it is good for
/// one join of one room in one place and cannot be replayed into another. The relay verifies it
/// against the public key in the same message and checks that the key hashes to the room for a
/// host; a guest signs with its own key, and the relay lets it in because the host will refuse
/// an unknown static in the handshake it cannot read.
public enum RelayJoin {
    /// The bytes both ends sign and verify: the challenge, the room, then the role.
    public static func message(room: RoomID, role: RelayRole, nonce: Data) -> Data {
        nonce + Data(room.rawValue.utf8) + Data(role.rawValue.utf8)
    }

    /// A device's signature over one challenge.
    public static func sign(
        identity: DeviceIdentity, room: RoomID, role: RelayRole, nonce: Data
    ) throws -> Data {
        try identity.signing.signature(for: message(room: room, role: role, nonce: nonce))
    }

    /// Whether that signature is good.
    public static func verify(
        signature: Data, publicKey: Data, room: RoomID, role: RelayRole, nonce: Data
    ) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(
            signature, for: message(room: room, role: role, nonce: nonce))
    }

    /// The join message a device sends, signed.
    public static func message(
        identity: DeviceIdentity, room: RoomID, role: RelayRole, nonce: Data
    ) throws -> RelayMessage {
        .join(
            room: room,
            publicKey: identity.publicKeys.signing,
            role: role,
            signature: try sign(identity: identity, room: room, role: role, nonce: nonce))
    }
}
