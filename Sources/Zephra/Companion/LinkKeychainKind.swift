import Foundation
import Security
import os

/// Which of macOS's two keychains this launch may use, worked out once.
///
/// The data-protection keychain is the one that honours `kSecAttrAccessible`, and it is where
/// the identity and the pairings belong: `ThisDeviceOnly` is the whole reason a Mac restored
/// from another Mac's backup has to be shown a code again. But reaching it needs an entitlement
/// that comes with a real signing identity, and a build signed ad hoc — every Debug build, and
/// so every `make build` — has none. Every write there comes back `errSecMissingEntitlement`,
/// the identity cannot be stored, and the link never opens a road: no listener, no pairing, and
/// nothing on screen to say why.
///
/// So the answer is asked once a launch and kept. The question is a delete of an account nothing
/// ever writes: with the entitlement that is `errSecItemNotFound`, without it
/// `errSecMissingEntitlement`, and either way nothing in either keychain moves.
nonisolated enum LinkKeychainKind: Sendable {
    /// The keychain that honours `kSecAttrAccessible`. What a signed build gets.
    case dataProtection
    /// The old file-based login keychain, where `kSecAttrAccessible` is ignored. All a build
    /// signed ad hoc can reach.
    case legacy

    /// What this launch is using, resolved the first time it is asked and logged once.
    static let current: LinkKeychainKind = {
        let kind = resolve()
        Logger(subsystem: "io.zephra", category: "companion")
            .info("companion keychain: \(kind.reason, privacy: .public)")
        return kind
    }()

    /// Whether a query should ask for the data-protection keychain.
    var usesDataProtection: Bool { self == .dataProtection }

    /// What the one log line says.
    private var reason: String {
        switch self {
        case .dataProtection: "data protection"
        case .legacy: "legacy, since this build is not signed for the data-protection keychain"
        }
    }

    /// Asks the data-protection keychain to delete something that was never there.
    private static func resolve() -> LinkKeychainKind {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LinkKeychain.service,
            kSecAttrAccount as String: probeAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemDelete(probe as CFDictionary) == errSecMissingEntitlement
            ? .legacy : .dataProtection
    }

    /// An account nothing ever writes, so asking costs nothing and removes nothing.
    private static let probeAccount = "entitlement-probe"
}
