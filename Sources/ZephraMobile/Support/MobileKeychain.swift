import Foundation
import Security
import ZephraLinkClient
import ZephraLinkProtocol

/// The two things the phone must not lose, kept where iOS keeps secrets: who this device is,
/// and which Mac it has paired with.
///
/// `LinkKeyStore` is a protocol precisely so this file exists in the app and nowhere else —
/// the link package is tested in milliseconds against `MemoryLinkKeyStore`, with no keychain
/// and no entitlement. Two generic-password items under one service, because they are lost
/// together and are worth nothing apart: an identity with no pairing is a device nobody knows,
/// and a pairing whose private keys are gone cannot complete a handshake.
///
/// `AfterFirstUnlockThisDeviceOnly` is the accessibility, for two reasons. The phone reconnects
/// as it comes to the foreground and while it is locked in a pocket, which rules out the
/// `WhenUnlocked` classes; and a backup restored onto another phone must not arrive already
/// paired with somebody's Mac, which is what `ThisDeviceOnly` says.
nonisolated struct MobileKeychain: HostPersistence {
    /// The service every item of ours is filed under.
    static let service = "io.zephra.link"

    /// Which of the two items: the account name inside the service.
    private enum Item: String {
        case identity = "device-identity"
        case host = "paired-host"
        case hosts = "paired-hosts-v2"
    }

    /// What the keychain said when it would not do as it was asked.
    ///
    /// It carries the `OSStatus` and nothing else on purpose: nothing above this can act on the
    /// difference between one failure and another, and the phone's answer to all of them is the
    /// same — pair again.
    struct Failure: Error {
        /// The status the Security framework returned.
        let status: OSStatus
    }

    func loadIdentity() throws -> DeviceIdentity? {
        guard let bytes = try read(.identity) else { return nil }
        return try DeviceIdentity(rawRepresentation: bytes)
    }

    func save(_ identity: DeviceIdentity) throws {
        try write(identity.rawRepresentation, to: .identity)
    }

    func loadPairedHost() throws -> PairedHost? {
        guard let bytes = try read(.host) else { return nil }
        return try LinkJSON.decode(PairedHost.self, from: bytes)
    }

    func save(_ host: PairedHost?) throws {
        guard let host else { return try delete(.host) }
        try write(try LinkJSON.encode(host), to: .host)
    }

    func readHosts() throws -> [HostPreference]? {
        guard let bytes = try read(.hosts) else { return nil }
        return try LinkJSON.decode([HostPreference].self, from: bytes)
    }

    func writeHosts(_ hosts: [HostPreference]) throws {
        try write(try LinkJSON.encode(hosts), to: .hosts)
    }

    /// One item's bytes, or nil where there is no such item.
    private func read(_ item: Item) throws -> Data? {
        var query = Self.query(for: item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    /// Puts bytes down, replacing whatever was there.
    ///
    /// Added first and updated on the collision rather than deleted and re-added: a delete that
    /// succeeds and an add that fails would leave the phone with no identity at all, which is
    /// every pairing gone.
    private func write(_ bytes: Data, to item: Item) throws {
        var query = Self.query(for: item)
        query[kSecValueData as String] = bytes
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecDuplicateItem else {
            guard status == errSecSuccess else { throw Failure(status: status) }
            return
        }
        let update = SecItemUpdate(
            Self.query(for: item) as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        guard update == errSecSuccess else { throw Failure(status: update) }
    }

    /// Takes one item away. An item that was never there is not a failure.
    private func delete(_ item: Item) throws {
        let status = SecItemDelete(Self.query(for: item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    /// What names one of our two items, and nothing else on the device.
    ///
    /// `kSecUseDataProtectionKeychain` is the default on iOS and asked for anyway: it is the
    /// only keychain that honours `kSecAttrAccessible`, it is what the Mac's `LinkKeychain` has
    /// to spell out, and one shape for both ends is one thing to know rather than two.
    private static func query(for item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
