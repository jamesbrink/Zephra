import CryptoKit
import Foundation

/// Proving a device may join a room.
///
/// The signature is over the relay's own challenge, the room and the role, so it is good for
/// one join of one room against one nonce and cannot be replayed into another. The relay
/// verifies it against the public key in the same message and checks that the key hashes to the
/// room — for a host only. A guest is admitted only when the key it signed with is on the host's
/// `allow` list, and only when no other guest holds the room.
public enum RelayJoin {
    /// How many bytes the relay's challenge is.
    public static let nonceByteCount = 32
    /// How long a challenge is good for, and it is single-use.
    public static let challengeLifetime: TimeInterval = 60
    /// The most keys a host's allow-list may carry. A longer one is `bad allow` and closes the
    /// connection, so the list is trimmed here rather than refused there.
    public static let allowLimit = 16

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
    ///
    /// `allow` is carried by a host and by nothing else: the raw signing keys of the devices it
    /// has paired, which is the set the relay admits a guest out of. The list is not signed,
    /// because the relay takes it only from the connection that has just proved it holds the
    /// room's own key — the signature over the challenge is what says this is that host. It is
    /// trimmed to `allowLimit`, which the caller has already ordered by what matters most.
    ///
    /// `open` is the host's too, and it is how a phone pairs for the first time at all: a device
    /// that has never paired is on no list, so without it the relay would refuse the one guest
    /// the code on screen was put up for. It is written only when true, and it buys a stranger
    /// nothing but a handshake — the Mac's own responder still refuses anything that cannot
    /// answer the code.
    public static func message(
        identity: DeviceIdentity, nonce: Data, room: RoomID, role: RelayRole,
        allow: [Data]? = nil, open: Bool = false
    ) throws -> RelayMessage {
        .join(
            room: room,
            publicKey: identity.publicKeys.signing,
            role: role,
            signature: try sign(identity: identity, nonce: nonce, room: room, role: role),
            allow: role == .host ? Array((allow ?? []).prefix(allowLimit)) : nil,
            open: role == .host && open ? true : nil)
    }
}
