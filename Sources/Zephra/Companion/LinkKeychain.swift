import Foundation
import ZephraLinkHost
import ZephraLinkProtocol

/// Where the companion link's secrets live between launches: this Mac's own identity, and the
/// phones it has agreed to talk to.
///
/// The keychain rather than preferences, because the identity is sixty-four bytes of private key
/// and the pairings are what stand in for a password on every reconnection. Both are generic
/// passwords under one service, accessible after the first unlock and never off this Mac:
/// `ThisDeviceOnly` keeps them out of a backup and out of iCloud, which is right for a key that
/// names one machine — a Mac restored from another Mac's backup should be a new device the
/// phones have to be shown a code for.
///
/// A `ZEPHRA_FRESH_START` launch reads and writes its own accounts, so pretending to be a new
/// Mac neither sees nor overwrites the real pairings, exactly as `AppSettings.store` does for
/// preferences.
struct LinkKeychain: PairingStore, Sendable {
    /// The one service every item here is filed under.
    static let service = "io.zephra.link"

    /// Where this Mac's private keys are.
    let identityAccount: String
    /// Where the list of paired phones is.
    let devicesAccount: String

    /// The keychain this launch should read. A fresh start gets accounts of its own.
    ///
    /// The answer is passed in rather than read here: `FreshStart.current` is main-actor state
    /// in an app target isolated to the main actor by default, and this type is `Sendable` so
    /// that a session can hold it off the main actor.
    init(isFreshStart: Bool) {
        let suffix = isFreshStart ? ".fresh" : ""
        identityAccount = "identity\(suffix)"
        devicesAccount = "devices\(suffix)"
    }

    /// This Mac's identity, made and stored the first time it is asked for.
    ///
    /// A new identity would look like a new device and every pairing would be gone, so the one
    /// on disk always wins. Bytes that are there but are not an identity — a key written by a
    /// build that stored something else — are replaced rather than thrown, since the alternative
    /// is an app that cannot start its link at all.
    func identity() throws -> DeviceIdentity {
        if let bytes = try read(identityAccount), let identity = try? DeviceIdentity(rawRepresentation: bytes) {
            return identity
        }
        let identity = DeviceIdentity()
        try write(identity.rawRepresentation, to: identityAccount)
        return identity
    }

    func load() throws -> [PairedDevice] {
        guard let bytes = try read(devicesAccount) else { return [] }
        return try JSONDecoder().decode([PairedDevice].self, from: bytes)
    }

    func save(_ devices: [PairedDevice]) throws {
        try write(try JSONEncoder().encode(devices), to: devicesAccount)
    }
}
