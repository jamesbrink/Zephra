import Foundation
import Security
import Testing

@testable import Zephra

/// Which store this build's signature allows, and how the keychain one spells an item when it is
/// the store in use.
@Suite("The link's secrets go where this build's signature allows")
struct LinkSecretStoreChoiceTests {
    @Test("a build signed ad hoc — the test host, and every local build — keeps them in files")
    func anAdHocBuildIsFiles() {
        // The host this runs in is the Debug app, signed `CODE_SIGN_IDENTITY "-"`, so it carries
        // no team identifier. That is the whole question `LinkKeychainKind` asks, and answering
        // it `.file` is what keeps a rebuilt app from asking for the login keychain's password
        // at every launch.
        #expect(LinkKeychainKind.current == .file)
        #expect(LinkKeychainKind.usesDataProtection == false)
        #expect(LinkKeychain.store(freshStart: nil) is LinkFileStore)
    }

    @Test("a query names the data-protection keychain exactly when this build may use one")
    func everyQueryOptsInWhereItCan() {
        let query = LinkKeychainStore.query("identity")
        // Not an unconditional `true`: reaching that keychain needs an entitlement only a real
        // signing identity carries, and asking for it without one returns
        // `errSecMissingEntitlement` on every write, which is the link never opening a road.
        #expect(
            query[kSecUseDataProtectionKeychain as String] as? Bool
                == (LinkKeychainKind.usesDataProtection ? true : nil))
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == LinkKeychainStore.service)
        #expect(query[kSecAttrAccount as String] as? String == "identity")
    }

    @Test("a build that cannot reach it falls back, so the query is the legacy one")
    func theFallbackIsTheLegacySpelling() {
        guard !LinkKeychainKind.usesDataProtection else { return }
        let query = LinkKeychainStore.query("identity")
        let legacy = LinkKeychainStore.legacyQuery("identity")
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
        #expect(query[kSecAttrAccount as String] as? String
            == legacy[kSecAttrAccount as String] as? String)
    }

    @Test("the legacy query is the same item without that flag, which is where an old build put it")
    func theLegacyQueryIsTheOldSpelling() {
        let legacy = LinkKeychainStore.legacyQuery("devices")
        #expect(legacy[kSecUseDataProtectionKeychain as String] == nil)
        #expect(legacy[kSecAttrAccount as String] as? String == "devices")
        #expect(legacy[kSecAttrService as String] as? String == LinkKeychainStore.service)
    }

    @Test("a fresh start names its own accounts, in both keychains")
    func aFreshStartIsAccountsOfItsOwn() {
        let real = LinkKeychainStore(isFreshStart: false)
        let fresh = LinkKeychainStore(isFreshStart: true)
        #expect(real.identityAccount == "identity")
        #expect(fresh.identityAccount == "identity.fresh")
        #expect(fresh.devicesAccount == "devices.fresh")
        #expect(
            LinkKeychainStore.legacyQuery(fresh.devicesAccount)[kSecAttrAccount as String] as? String
                == "devices.fresh")
    }
}
