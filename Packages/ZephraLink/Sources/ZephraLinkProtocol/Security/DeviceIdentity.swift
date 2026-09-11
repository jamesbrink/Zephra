import CryptoKit
import Foundation

/// One device's long-lived private keys: who it is, for as long as the pairing lasts.
///
/// Held as raw bytes so the Mac can put it in the keychain and the phone in its own, and read
/// back the same identity after a relaunch: a new identity would look like a new device and
/// every pairing would be gone.
public struct DeviceIdentity: Sendable {
    /// How many bytes `rawRepresentation` is: two thirty-two byte private keys.
    public static let rawByteCount = 64

    /// The key agreement half, which every shared secret in the handshake is built from.
    public let agreement: Curve25519.KeyAgreement.PrivateKey
    /// The signing half, which proves a relay join and names the room.
    public let signing: Curve25519.Signing.PrivateKey

    /// A brand new identity.
    public init() {
        agreement = Curve25519.KeyAgreement.PrivateKey()
        signing = Curve25519.Signing.PrivateKey()
    }

    /// The identity those bytes are: agreement first, signing second.
    public init(rawRepresentation: Data) throws {
        guard rawRepresentation.count == Self.rawByteCount else {
            throw LinkError(code: .badRequest, reason: "That is not a device identity.")
        }
        let bytes = Data(rawRepresentation)
        agreement = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: bytes.prefix(32))
        signing = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes.suffix(32))
    }

    /// The bytes to keep, in the order `init(rawRepresentation:)` reads them.
    public var rawRepresentation: Data {
        agreement.rawRepresentation + signing.rawRepresentation
    }

    /// What this device publishes about itself.
    public var publicKeys: DevicePublicKeys {
        DevicePublicKeys(
            keyAgreement: agreement.publicKey.rawRepresentation,
            signing: signing.publicKey.rawRepresentation)
    }

    /// The relay room this device is reachable in, when it is the host.
    public var roomID: RoomID { publicKeys.roomID }
}
