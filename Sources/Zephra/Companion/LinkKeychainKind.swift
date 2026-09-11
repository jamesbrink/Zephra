import Foundation
import Security
import os

/// Where this launch may keep the link's secrets, worked out once from this build's signature.
///
/// Three answers, because macOS has two keychains and a locally built app is comfortable in
/// neither:
///
/// - The **data-protection** keychain is the one that honours `kSecAttrAccessible`, and it is
///   where the identity and the pairings belong: `ThisDeviceOnly` is the whole reason a Mac
///   restored from another Mac's backup has to be shown a code again. Reaching it needs an
///   entitlement that comes with a real signing identity.
/// - The **legacy** file-based login keychain is where a signed build lands if that entitlement
///   is refused after all. It is reached lazily, on the first call that comes back
///   `errSecMissingEntitlement`, rather than through a probe: a probe is a keychain call of its
///   own, and the point of all this is to make fewer of them.
/// - **Files** under Application Support are what a build signed ad hoc gets, and such a build
///   never queries a keychain at all. Every `make run`, `make build` and `CODE_SIGN_IDENTITY "-"`
///   build carries a brand new signature, so the login keychain asks for the password every time
///   the rebuilt app touches items an earlier build created — at launch and on every pairing
///   write, until the next rebuild, when "Always Allow" stops meaning anything again. A file in a
///   folder only this user can read asks nothing, which is the right trade for a build that is
///   rebuilt ten times an hour.
///
/// The question is the team identifier in this code's own signing information: present means a
/// real identity, absent or empty means ad hoc. Nothing is written, read or deleted to find out.
nonisolated enum LinkKeychainKind: Sendable {
    /// The keychain that honours `kSecAttrAccessible`. What a Developer ID build gets.
    case dataProtection
    /// The old file-based login keychain, where `kSecAttrAccessible` is ignored. Where a signed
    /// build falls back to if the entitlement is refused after all.
    case legacy
    /// Two files under Application Support. What a build signed ad hoc gets.
    case file

    /// What this launch is using, resolved the first time it is asked and logged once.
    static let current: LinkKeychainKind = {
        let kind = resolve()
        logger.info("companion secrets: \(kind.reason, privacy: .public)")
        return kind
    }()

    /// Whether a keychain query should ask for the data-protection keychain right now.
    ///
    /// Not a constant: a build carrying a team identifier may still be refused the entitlement,
    /// and the first call that is refused latches this to false for the rest of the process.
    static var usesDataProtection: Bool {
        current == .dataProtection && !refused.withLock { $0 }
    }

    /// Records that the data-protection keychain refused this build's entitlement, so every call
    /// after this one is spelled the legacy way. Said once.
    static func fallBackToLegacy() {
        let first = refused.withLock { refused -> Bool in
            defer { refused = true }
            return !refused
        }
        guard first else { return }
        logger.info(
            "companion secrets: legacy keychain, since the data-protection one refused this build")
    }

    /// What the one log line says.
    private var reason: String {
        switch self {
        case .dataProtection: "data-protection keychain"
        case .legacy: "legacy keychain"
        case .file:
            "files under Application Support, since this build is signed ad hoc; a locally built "
                + "Zephra is paired once per machine rather than once per rebuild, and the first "
                + "launch after this change asks for a code again"
        }
    }

    /// Whether this code carries a team identifier, which is what a real signing identity gives
    /// it and an ad-hoc signature does not.
    private static func resolve() -> LinkKeychainKind {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return .file }
        var information: CFDictionary?
        let read = SecCodeCopySigningInformation(
            unsafeBitCast(code, to: SecStaticCode.self),
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information)
        guard read == errSecSuccess,
              let signing = information as? [String: Any],
              let team = signing[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty
        else { return .file }
        return .dataProtection
    }

    /// Whether the data-protection keychain has already refused this build.
    private static let refused = OSAllocatedUnfairLock(initialState: false)

    /// The one logger this Mac's link secrets speak through.
    private static let logger = Logger(subsystem: "io.zephra", category: "companion")
}
