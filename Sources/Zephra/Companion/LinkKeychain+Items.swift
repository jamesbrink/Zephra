import Foundation
import Security

/// The three Security calls behind the two properties above.
///
/// Kept apart so `LinkKeychain` reads as what it stores rather than as `CFDictionary`
/// arithmetic. Every item is a generic password under one service, so a reinstall that clears
/// the keychain simply unpairs every phone, which is the right answer for keys a person can see
/// and revoke in Settings.
extension LinkKeychain {
    /// What one item holds, or nil when there is no such item.
    func read(_ account: String) throws -> Data? {
        var query = Self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw LinkKeychainFailure(status: status)
        }
    }

    /// Puts bytes in one item, adding it the first time and updating it after.
    func write(_ bytes: Data, to account: String) throws {
        let query = Self.query(account)
        let update = [kSecValueData as String: bytes]
        let updated = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw LinkKeychainFailure(status: updated) }
        var item = query
        item[kSecValueData as String] = bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw LinkKeychainFailure(status: added) }
    }

    /// Removes one item, for a reset that should look like a Mac that has never linked.
    func removeAll() throws {
        for account in [identityAccount, devicesAccount] {
            let status = SecItemDelete(Self.query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw LinkKeychainFailure(status: status)
            }
        }
    }

    /// The item one account names.
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A keychain call that did not work, with the code it gave.
///
/// Carried rather than swallowed: a locked keychain is not an empty list of devices, and
/// treating it as one would quietly unpair every phone.
struct LinkKeychainFailure: Error, LocalizedError {
    /// The `OSStatus` the Security framework returned.
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        return "The keychain could not be read or written: \(detail)"
    }
}
