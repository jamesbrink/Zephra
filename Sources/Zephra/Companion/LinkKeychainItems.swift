import Foundation
import Security

/// The four Security calls the link's secrets are kept by, as one injected thing.
///
/// `LinkKeychainStore` is otherwise untestable: every one of these reaches the real keychain of
/// the Mac the tests are running on, and the migration this seam exists for — an item written by
/// an older build, moved across and then deleted — is exactly the path that once deleted the only
/// copy of this Mac's identity. A double that answers `errSecMissingEntitlement` on a write and
/// holds items per keychain is what pins it.
///
/// Statuses rather than errors, because the statuses are the whole answer: `errSecItemNotFound`
/// is "no such item", `errSecMissingEntitlement` is "not this keychain, try the other one", and
/// only the store above knows which of those is a failure.
nonisolated protocol LinkKeychainItems: Sendable {
    /// What one query matches, and what the Security framework said about it.
    func copy(_ query: [String: Any]) -> (status: OSStatus, bytes: Data?)
    /// Puts new bytes in the item a query names.
    func update(_ query: [String: Any], to bytes: Data) -> OSStatus
    /// Adds an item that is not there yet.
    func add(_ item: [String: Any]) -> OSStatus
    /// Takes one item away.
    func delete(_ query: [String: Any]) -> OSStatus
}
