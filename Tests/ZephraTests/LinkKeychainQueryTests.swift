import Foundation
import Security
import Testing

@testable import Zephra

/// Which keychain this Mac's link secrets live in, which is what decides whether the
/// accessibility asked for means anything at all.
@Suite("The link's keychain items ask for the best keychain this build can reach")
struct LinkKeychainQueryTests {
    @Test("a query names the data-protection keychain exactly when this build may use one")
    func everyQueryOptsInWhereItCan() {
        let query = LinkKeychain.query("identity")
        // Not an unconditional `true`: reaching that keychain needs an entitlement only a real
        // signing identity carries, and the test host — like every Debug build — is signed ad
        // hoc. Asking for it there returns `errSecMissingEntitlement` on every write, which is
        // the link never opening a road at all.
        #expect(
            query[kSecUseDataProtectionKeychain as String] as? Bool
                == (LinkKeychainKind.current == .dataProtection ? true : nil))
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == LinkKeychain.service)
        #expect(query[kSecAttrAccount as String] as? String == "identity")
    }

    @Test("a build that cannot reach it falls back, so the query is the legacy one")
    func theFallbackIsTheLegacySpelling() {
        guard LinkKeychainKind.current == .legacy else { return }
        let query = LinkKeychain.query("identity")
        let legacy = LinkKeychain.legacyQuery("identity")
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
        #expect(query[kSecAttrAccount as String] as? String
            == legacy[kSecAttrAccount as String] as? String)
    }

    @Test("the legacy query is the same item without that flag, which is where an old build put it")
    func theLegacyQueryIsTheOldSpelling() {
        let legacy = LinkKeychain.legacyQuery("devices")
        #expect(legacy[kSecUseDataProtectionKeychain as String] == nil)
        #expect(legacy[kSecAttrAccount as String] as? String == "devices")
        #expect(legacy[kSecAttrService as String] as? String == LinkKeychain.service)
    }

    @Test("a fresh start names its own accounts, in both keychains")
    func aFreshStartIsAccountsOfItsOwn() {
        let real = LinkKeychain(isFreshStart: false)
        let fresh = LinkKeychain(isFreshStart: true)
        #expect(real.identityAccount == "identity")
        #expect(fresh.identityAccount == "identity.fresh")
        #expect(fresh.devicesAccount == "devices.fresh")
        #expect(
            LinkKeychain.legacyQuery(fresh.devicesAccount)[kSecAttrAccount as String] as? String
                == "devices.fresh")
    }
}
