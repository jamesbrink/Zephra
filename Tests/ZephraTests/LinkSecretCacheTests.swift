import Foundation
import Synchronization
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import Zephra

/// How often a launch touches the store under it, which on a signed build is how often a
/// password prompt can appear.
@Suite("The link's secrets are read once a launch and written only when it is worth a call")
struct LinkSecretCacheTests {
    /// A store that counts what it is asked, standing in for the keychain.
    private nonisolated final class Spy: LinkSecretStore, Sendable {
        let calls = Mutex((identityReads: 0, identityWrites: 0, loads: 0, saves: 0))
        private let devices = Mutex<[PairedDevice]>([])

        func identityBytes() throws -> Data? {
            calls.withLock { $0.identityReads += 1 }
            return nil
        }

        func writeIdentity(_ bytes: Data) throws { calls.withLock { $0.identityWrites += 1 } }

        func load() throws -> [PairedDevice] {
            calls.withLock { $0.loads += 1 }
            return devices.withLock { $0 }
        }

        func save(_ devices: [PairedDevice]) throws {
            calls.withLock { $0.saves += 1 }
            self.devices.withLock { $0 = devices }
        }

        func removeAll() throws {}

        var saves: Int { calls.withLock { $0.saves } }
        var reads: (identity: Int, devices: Int) {
            calls.withLock { ($0.identityReads, $0.loads) }
        }
    }

    /// A clock the test moves by hand, so a minute passes without waiting one.
    private nonisolated final class Clock: Sendable {
        private let instant = Mutex(Date(timeIntervalSince1970: 1_000))
        var now: @Sendable () -> Date { { self.instant.withLock { $0 } } }
        func advance(_ seconds: TimeInterval) {
            instant.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    private func device(_ name: String, lastSeen: Date?) -> PairedDevice {
        PairedDevice(
            keys: DeviceIdentity().publicKeys, name: name, pairedAt: Date(timeIntervalSince1970: 1),
            lastSeen: lastSeen)
    }

    @Test("the launch sequence reads each secret once, however often it is asked")
    func aLaunchReadsOnce() throws {
        let spy = Spy()
        let cache = LinkSecretCache(over: spy)
        _ = try cache.identity()
        _ = try cache.identity()
        _ = try cache.load()
        _ = try cache.load()
        _ = try cache.load()
        #expect(spy.reads == (identity: 1, devices: 1))
        // The identity was absent, so it was made and written once; nothing read it back.
        #expect(spy.calls.withLock { $0.identityWrites } == 1)
    }

    @Test("a pairing is written at once, and reading after a write asks the store nothing")
    func aRealChangeIsWrittenThrough() throws {
        let spy = Spy()
        let cache = LinkSecretCache(over: spy)
        _ = try cache.load()
        try cache.save([device("James's iPhone", lastSeen: nil)])
        #expect(spy.saves == 1)
        #expect(try cache.load().count == 1)
        #expect(spy.reads.devices == 1)
        // The same list again is not a change and is not worth a call.
        try cache.save(try cache.load())
        #expect(spy.saves == 1)
    }

    @Test("a phone coming back moves lastSeen at most once a minute")
    func lastSeenIsRateLimited() throws {
        let clock = Clock()
        let spy = Spy()
        let cache = LinkSecretCache(over: spy, now: clock.now)
        _ = try cache.load()
        let phone = device("James's iPhone", lastSeen: nil)
        try cache.save([phone])
        #expect(spy.saves == 1)
        for second in 1...3 {
            clock.advance(1)
            var seen = phone
            seen.lastSeen = Date(timeIntervalSince1970: TimeInterval(second))
            try cache.save([seen])
        }
        #expect(spy.saves == 1)
        // Once the minute is up the next reconnection is worth the call.
        clock.advance(LinkSecretCache.cosmeticInterval)
        var seen = phone
        seen.lastSeen = Date(timeIntervalSince1970: 99)
        try cache.save([seen])
        #expect(spy.saves == 2)
    }

    @Test("a real change carries the deferred lastSeen with it rather than waiting")
    func aRealChangeCarriesTheCosmeticOne() throws {
        let clock = Clock()
        let spy = Spy()
        let cache = LinkSecretCache(over: spy, now: clock.now)
        _ = try cache.load()
        let phone = device("James's iPhone", lastSeen: nil)
        try cache.save([phone])
        var seen = phone
        seen.lastSeen = Date(timeIntervalSince1970: 5)
        try cache.save([seen])
        #expect(spy.saves == 1)
        try cache.save([seen, device("The iPad", lastSeen: nil)])
        #expect(spy.saves == 2)
        #expect(try cache.load().first?.lastSeen == seen.lastSeen)
    }
}
