import Foundation
import ZephraLinkHost

/// The link's secrets as two files, for a build whose signature is its own every time.
///
/// `identity` is the raw sixty-four bytes and `devices.json` is the paired phones, both under
/// `<Application Support>/Zephra/Companion`, the folder at 0700 and each file at 0600, written
/// through a temporary sibling and renamed into place so a half-written list is never read.
///
/// Why a file and not the keychain: an ad-hoc signature cannot reach the data-protection
/// keychain, and the login keychain it falls back to identifies an app by its signature, which a
/// local build changes on every `make build`. The rebuilt app asking for the password before it
/// can read what the last build wrote is not a security decision anybody made; it is the login
/// keychain doing exactly its job to an app that is a different app every hour.
///
/// Nothing is migrated out of the keychain into here, deliberately: reading the item would raise
/// the very prompt this exists to avoid. A local build therefore pairs its phone once more, and
/// the log line says so.
struct LinkFileStore: LinkSecretStore, Sendable {
    /// The folder both files live in.
    let folder: URL

    /// Where this launch keeps them. A fresh start gets a folder of its own, under the
    /// throwaway root, exactly as its models and images do.
    init(freshStart: FreshStart?) {
        folder = (freshStart?.root ?? URL.applicationSupportDirectory.appending(
            path: "Zephra", directoryHint: .isDirectory))
            .appending(path: "Companion", directoryHint: .isDirectory)
    }

    /// A store over one folder, for tests.
    init(folder: URL) { self.folder = folder }

    func identityBytes() throws -> Data? { try read(Self.identityFile) }

    func writeIdentity(_ bytes: Data) throws { try write(bytes, to: Self.identityFile) }

    func load() throws -> [PairedDevice] {
        guard let bytes = try read(Self.devicesFile) else { return [] }
        return try JSONDecoder().decode([PairedDevice].self, from: bytes)
    }

    func save(_ devices: [PairedDevice]) throws {
        try write(try JSONEncoder().encode(devices), to: Self.devicesFile)
    }

    func removeAll() throws {
        for name in [Self.identityFile, Self.devicesFile] {
            let url = folder.appending(path: name)
            do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {}
        }
    }

    /// The raw private keys, as `DeviceIdentity.rawRepresentation` spells them.
    static let identityFile = "identity"
    /// The paired phones, as `PairedDevice` encodes them.
    static let devicesFile = "devices.json"
}
