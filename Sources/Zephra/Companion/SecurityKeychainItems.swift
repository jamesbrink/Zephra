import Foundation
import Security

/// The real keychain: `LinkKeychainItems` as the Security framework answers it.
///
/// Nothing decides anything here. The two flags a read needs — data back rather than attributes,
/// and one item rather than all of them — are added here because they are Security's spelling and
/// not the link's, so a double stands in for this type without knowing either.
nonisolated struct SecurityKeychainItems: LinkKeychainItems {
    func copy(_ query: [String: Any]) -> (status: OSStatus, bytes: Data?) {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [String: Any], to bytes: Data) -> OSStatus {
        SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
    }

    func add(_ item: [String: Any]) -> OSStatus { SecItemAdd(item as CFDictionary, nil) }

    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}
