import Foundation
import Security

/// The Security calls behind the properties above, and the one migration between two keychains.
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
/// `errSecMissingEntitlement`, which latches the store's `LinkKeychainLatch` to the legacy
/// spelling and tries again — rather than by a probe, which would be one more keychain call in a
/// file whose whole purpose is to make fewer of them.
///
/// **The migration never deletes what it did not move.** A write refused the data-protection
/// keychain lands in the legacy item itself, and the delete that used to follow it took the only
/// copy there was: the next launch found no identity, minted a new one, and every phone paired
/// with that Mac was talking to a machine that no longer existed. So the spelling is read once at
/// the top and again after the write, and the delete happens only where both say the bytes went
/// somewhere else.
extension LinkKeychainStore {
    /// What one item holds, or nil when there is no such item.
    func read(_ account: String) throws -> Data? {
        let dataProtection = latch.usesDataProtection
        do {
            if let bytes = try copy(Self.query(account, dataProtection: dataProtection)) {
                return bytes
            }
        } catch let failure as LinkKeychainFailure where failure.isMissingEntitlement {
            guard dataProtection else { throw failure }
            latch.fallBackToLegacy()
            return try read(account)
        }
        // Nothing to migrate when the query above was already the legacy spelling: both queries
        // name one item, and the copy has answered for it.
        guard dataProtection else { return nil }
        guard let legacy = try copy(Self.legacyQuery(account)) else { return nil }
        try write(legacy, to: account)
        // The write may have been refused and fallen back, in which case it landed in the very
        // item `legacyQuery` names. Deleting it now would delete the only copy there is.
        guard latch.usesDataProtection else { return legacy }
        try remove(Self.legacyQuery(account))
        return legacy
    }

    /// Puts bytes in one item, adding it the first time and updating it after.
    func write(_ bytes: Data, to account: String) throws {
        let dataProtection = latch.usesDataProtection
        let query = Self.query(account, dataProtection: dataProtection)
        let updated = items.update(query, to: bytes)
        if updated == errSecSuccess { return }
        if updated == errSecMissingEntitlement {
            return try writeOnLegacy(bytes, to: account, from: dataProtection)
        }
        guard updated == errSecItemNotFound else { throw LinkKeychainFailure(status: updated) }
        var item = query
        item[kSecValueData as String] = bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = items.add(item)
        if added == errSecMissingEntitlement {
            return try writeOnLegacy(bytes, to: account, from: dataProtection)
        }
        guard added == errSecSuccess else { throw LinkKeychainFailure(status: added) }
    }

    /// Removes both items, for a reset that should look like a Mac that has never linked.
    ///
    /// Both keychains, since a Mac that linked under an older build may still have the item
    /// where that build put it.
    func removeAll() throws {
        for account in [identityAccount, devicesAccount] {
            try remove(Self.query(account, dataProtection: latch.usesDataProtection))
            try remove(Self.legacyQuery(account))
        }
    }

    /// The data-protection keychain refusing a write: latch it and try the old one, once.
    ///
    /// Once, because the legacy spelling answering the same way is a failure and not another
    /// fall back — a keychain that says `errSecMissingEntitlement` to everything would otherwise
    /// recurse until the stack ran out.
    private func writeOnLegacy(_ bytes: Data, to account: String, from dataProtection: Bool) throws {
        guard dataProtection else { throw LinkKeychainFailure(status: errSecMissingEntitlement) }
        latch.fallBackToLegacy()
        try write(bytes, to: account)
    }

    /// One item's bytes under one query, or nil when there is no such item.
    private func copy(_ query: [String: Any]) throws -> Data? {
        let answer = items.copy(query)
        switch answer.status {
        case errSecSuccess: return answer.bytes
        case errSecItemNotFound: return nil
        default: throw LinkKeychainFailure(status: answer.status)
        }
    }

    /// Takes one item away. An item that was never there is not a failure.
    private func remove(_ query: [String: Any]) throws {
        let status = items.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound
            || status == errSecMissingEntitlement
        else { throw LinkKeychainFailure(status: status) }
    }
}
