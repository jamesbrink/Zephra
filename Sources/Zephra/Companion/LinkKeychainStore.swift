import Foundation
import ZephraLinkHost

/// The link's secrets as two generic passwords under one service, for a build a real signing
/// identity stands behind.
///
/// The keychain rather than files, because the identity is sixty-four bytes of private key and
/// the pairings are what stand in for a password on every reconnection. Both are accessible
/// after the first unlock and never off this Mac: `ThisDeviceOnly` keeps them out of a backup
/// and out of iCloud, which is right for a key that names one machine — a Mac restored from
/// another Mac's backup should be a new device the phones have to be shown a code for.
///
/// A `ZEPHRA_FRESH_START` launch reads and writes accounts of its own, so pretending to be a new
/// Mac neither sees nor overwrites the real pairings, exactly as `AppSettings.store` does for
/// preferences.
struct LinkKeychainStore: LinkSecretStore, Sendable {
    /// The one service every item here is filed under.
    static let service = "io.zephra.link"

    /// Where this Mac's private keys are.
    let identityAccount: String
    /// Where the list of paired phones is.
    let devicesAccount: String

    /// The accounts this launch should read. A fresh start gets accounts of its own.
    ///
    /// The answer is passed in rather than read here: `FreshStart.current` is main-actor state
    /// in an app target isolated to the main actor by default, and this type is `Sendable` so
    /// that a session can hold it off the main actor.
    init(isFreshStart: Bool) {
        let suffix = isFreshStart ? ".fresh" : ""
        identityAccount = "identity\(suffix)"
        devicesAccount = "devices\(suffix)"
    }

    func identityBytes() throws -> Data? { try read(identityAccount) }

    func writeIdentity(_ bytes: Data) throws { try write(bytes, to: identityAccount) }

    func load() throws -> [PairedDevice] {
        guard let bytes = try read(devicesAccount) else { return [] }
        return try JSONDecoder().decode([PairedDevice].self, from: bytes)
    }

    func save(_ devices: [PairedDevice]) throws {
        try write(try JSONEncoder().encode(devices), to: devicesAccount)
    }
}
