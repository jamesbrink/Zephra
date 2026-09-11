import Foundation
import Security

/// The three Security calls behind the properties above.
///
/// Kept apart so `LinkKeychainStore` reads as what it stores rather than as `CFDictionary`
/// arithmetic. Every item is a generic password under one service, so a reinstall that clears
/// the keychain simply unpairs every phone, which is the right answer for keys a person can see
/// and revoke in Settings.
///
/// Every query asks for the **data-protection** keychain. On macOS the default is the old
/// file-based keychain, where `kSecAttrAccessible` is not honoured: the identity and the
/// pairings would sit there under whatever the login keychain's own unlock state happened to be,
/// and `ThisDeviceOnly` — the whole reason a restored backup is a new Mac — would mean nothing.
/// An item written by a build before this is found by `legacyQuery`, moved across on the first
/// read, and deleted from where it was.
///
/// Reaching that keychain needs an entitlement, and a build that carries a team identifier may
/// still be refused it. That is found out here, on the first call that comes back
/// `errSecMissingEntitlement`, which latches `LinkKeychainKind` to the legacy spelling and tries
/// again — rather than by a probe, which would be one more keychain call in a file whose whole
/// purpose is to make fewer of them.
extension LinkKeychainStore {
    /// What one item holds, or nil when there is no such item.
    func read(_ account: String) throws -> Data? {
        do {
            if let bytes = try copy(Self.query(account)) { return bytes }
        } catch let failure as LinkKeychainFailure where failure.isMissingEntitlement {
            LinkKeychainKind.fallBackToLegacy()
            return try read(account)
        }
        guard let legacy = try copy(Self.legacyQuery(account)) else { return nil }
        try write(legacy, to: account)
        try remove(Self.legacyQuery(account))
        return legacy
    }

    /// Puts bytes in one item, adding it the first time and updating it after.
    func write(_ bytes: Data, to account: String) throws {
        let query = Self.query(account)
        let update = [kSecValueData as String: bytes]
        let updated = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return }
        if updated == errSecMissingEntitlement {
            LinkKeychainKind.fallBackToLegacy()
            return try write(bytes, to: account)
        }
        guard updated == errSecItemNotFound else { throw LinkKeychainFailure(status: updated) }
        var item = query
        item[kSecValueData as String] = bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecMissingEntitlement {
            LinkKeychainKind.fallBackToLegacy()
            return try write(bytes, to: account)
        }
        guard added == errSecSuccess else { throw LinkKeychainFailure(status: added) }
    }

    /// Removes both items, for a reset that should look like a Mac that has never linked.
    ///
    /// Both keychains, since a Mac that linked under an older build may still have the item
    /// where that build put it.
    func removeAll() throws {
        for account in [identityAccount, devicesAccount] {
            try remove(Self.query(account))
            try remove(Self.legacyQuery(account))
        }
    }

    /// One item's bytes under one query, or nil when there is no such item.
    private func copy(_ query: [String: Any]) throws -> Data? {
        var query = query
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

    /// Takes one item away. An item that was never there is not a failure.
    private func remove(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
            || status == errSecMissingEntitlement
        else { throw LinkKeychainFailure(status: status) }
    }

    /// The item one account names, in the best keychain this build can reach.
    ///
    /// The data-protection keychain while this build is allowed one, and the old keychain after
    /// it has been refused. Where the answer is the legacy spelling this is `legacyQuery`, which
    /// makes the migration above a lookup that finds the item where it already is and moves
    /// nothing.
    static func query(_ account: String) -> [String: Any] {
        var query = base(account)
        guard LinkKeychainKind.usesDataProtection else { return query }
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    /// The same item as a build before the data-protection keychain wrote it.
    static func legacyQuery(_ account: String) -> [String: Any] { base(account) }

    /// What both spellings have in common.
    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
