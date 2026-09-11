import Foundation
import Security
import Testing

@testable import Zephra

/// Which keychain this Mac's link secrets live in, which is what decides whether the
/// accessibility asked for means anything at all.
@Suite("The link's keychain items ask for the data-protection keychain")
struct LinkKeychainQueryTests {
    @Test("every query names the data-protection keychain")
    func everyQueryOptsIn() {
        let query = LinkKeychain.query("identity")
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == LinkKeychain.service)
        #expect(query[kSecAttrAccount as String] as? String == "identity")
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
