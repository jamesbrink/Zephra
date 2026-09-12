import Foundation
import Security
import Synchronization
import Testing

@testable import Zephra

/// Moving an older build's items into the data-protection keychain, and what happens when this
/// build turns out not to be allowed that keychain after all.
@Suite("A keychain migration never deletes the only copy of a secret")
struct LinkKeychainMigrationTests {
    /// Two keychains in memory, told apart the way the Security framework tells them apart: by
    /// whether the query asks for the data-protection one.
    ///
    /// `refusesDataProtection` is the failure this suite is about — a build that carries a team
    /// identifier and is refused the entitlement anyway, which answers every write to that
    /// keychain `errSecMissingEntitlement`.
    private nonisolated final class Keychains: LinkKeychainItems, Sendable {
        private let state = Mutex(State())

        init(refusesDataProtection: Bool, legacy: [String: Data] = [:]) {
            state.withLock {
                $0.refuses = refusesDataProtection
                $0.legacy = legacy
            }
        }

        func copy(_ query: [String: Any]) -> (status: OSStatus, bytes: Data?) {
            state.withLock { state in
                guard let bytes = state.items(query)[Self.account(query)] else {
                    return (errSecItemNotFound, nil)
                }
                return (errSecSuccess, bytes)
            }
        }

        func update(_ query: [String: Any], to bytes: Data) -> OSStatus {
            state.withLock { state in
                guard !(Self.isDataProtection(query) && state.refuses) else {
                    return errSecMissingEntitlement
                }
                guard state.items(query)[Self.account(query)] != nil else {
                    return errSecItemNotFound
                }
                state.put(bytes, at: Self.account(query), dataProtection: Self.isDataProtection(query))
                return errSecSuccess
            }
        }

        func add(_ item: [String: Any]) -> OSStatus {
            state.withLock { state in
                guard !(Self.isDataProtection(item) && state.refuses) else {
                    return errSecMissingEntitlement
                }
                guard let bytes = item[kSecValueData as String] as? Data else { return errSecParam }
                state.put(bytes, at: Self.account(item), dataProtection: Self.isDataProtection(item))
                return errSecSuccess
            }
        }

        func delete(_ query: [String: Any]) -> OSStatus {
            state.withLock { state in
                let account = Self.account(query)
                let dataProtection = Self.isDataProtection(query)
                guard state.items(query)[account] != nil else { return errSecItemNotFound }
                state.remove(account, dataProtection: dataProtection)
                return errSecSuccess
            }
        }

        /// What each keychain holds right now.
        var contents: (dataProtection: [String: Data], legacy: [String: Data]) {
            state.withLock { ($0.dataProtection, $0.legacy) }
        }

        private static func account(_ query: [String: Any]) -> String {
            query[kSecAttrAccount as String] as? String ?? ""
        }

        private static func isDataProtection(_ query: [String: Any]) -> Bool {
            query[kSecUseDataProtectionKeychain as String] as? Bool == true
        }

        private struct State {
            var refuses = false
            var dataProtection: [String: Data] = [:]
            var legacy: [String: Data] = [:]

            func items(_ query: [String: Any]) -> [String: Data] {
                Keychains.isDataProtection(query) ? dataProtection : legacy
            }

            mutating func put(_ bytes: Data, at account: String, dataProtection: Bool) {
                if dataProtection { self.dataProtection[account] = bytes } else { legacy[account] = bytes }
            }

            mutating func remove(_ account: String, dataProtection: Bool) {
                if dataProtection { self.dataProtection[account] = nil } else { legacy[account] = nil }
            }
        }
    }

    private static let identity = Data(repeating: 7, count: 64)

    @Test("a migration that cannot write to the new keychain leaves the legacy item where it was")
    func aRefusedMigrationKeepsTheOldItem() throws {
        let keychains = Keychains(
            refusesDataProtection: true, legacy: ["identity": Self.identity])
        let store = LinkKeychainStore(
            isFreshStart: false, items: keychains, latch: LinkKeychainLatch(usesDataProtection: true))

        #expect(try store.identityBytes() == Self.identity)
        // The write fell back to the keychain the bytes were already in, so there was nothing to
        // delete. Deleting anyway is how a Mac lost its identity and every phone paired to it.
        #expect(keychains.contents.legacy["identity"] == Self.identity)
        #expect(keychains.contents.dataProtection.isEmpty)
        // And the next read finds it, which is the whole point: a relaunch is not a new Mac.
        #expect(try store.identityBytes() == Self.identity)
    }

    @Test("a migration that can write moves the item across and clears the old one")
    func aMigrationThatWorksMoves() throws {
        let keychains = Keychains(
            refusesDataProtection: false, legacy: ["identity": Self.identity])
        let store = LinkKeychainStore(
            isFreshStart: false, items: keychains, latch: LinkKeychainLatch(usesDataProtection: true))

        #expect(try store.identityBytes() == Self.identity)
        #expect(keychains.contents.dataProtection["identity"] == Self.identity)
        #expect(keychains.contents.legacy["identity"] == nil)
    }

    @Test("both secrets read one answer, and the one that is refused settles it for the other")
    func theLatchIsResolvedOnceForBothReads() throws {
        let keychains = Keychains(
            refusesDataProtection: true,
            legacy: ["identity": Self.identity, "devices": Data("[]".utf8)])
        let latch = LinkKeychainLatch(usesDataProtection: true)
        let store = LinkKeychainStore(isFreshStart: false, items: keychains, latch: latch)

        #expect(try store.identityBytes() == Self.identity)
        #expect(latch.usesDataProtection == false)
        #expect(try store.load().isEmpty)
        // Neither read left anything in a keychain this build cannot reach, and neither deleted
        // what it read: both secrets are still where the older build put them.
        #expect(keychains.contents.dataProtection.isEmpty)
        #expect(keychains.contents.legacy.keys.sorted() == ["devices", "identity"])
    }

    @Test("a launch already on the legacy keychain asks for nothing it cannot have")
    func aLatchedLaunchNeverAsksForDataProtection() throws {
        let keychains = Keychains(
            refusesDataProtection: true, legacy: ["identity": Self.identity])
        let store = LinkKeychainStore(
            isFreshStart: false, items: keychains,
            latch: LinkKeychainLatch(usesDataProtection: false))

        #expect(try store.identityBytes() == Self.identity)
        #expect(keychains.contents.legacy["identity"] == Self.identity)
        try store.writeIdentity(Data(repeating: 9, count: 64))
        #expect(keychains.contents.dataProtection.isEmpty)
    }
}
