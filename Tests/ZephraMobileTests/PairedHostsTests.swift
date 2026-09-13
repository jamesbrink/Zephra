import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@Suite("Pairing migration preserves identity and scopes every write")
struct PairedHostsTests {
    private func host(_ name: String) -> PairedHost {
        let identity = DeviceIdentity()
        return PairedHost(name: name, keys: identity.publicKeys, endpoints: [], roomID: identity.roomID,
            pairedAt: Date(timeIntervalSince1970: 0))
    }
    @Test("Legacy migration is idempotent and a forgotten host never resurrects")
    func migration() throws {
        let disk = MemoryHostPersistence()
        let prior = host("Same Name")
        disk.legacy = prior
        let store = try PairedHosts(keychain: disk)
        #expect(store.all().map(\.host) == [prior])
        let identity = store.identity.publicKeys
        try store.remove(HostID(keys: prior.keys))
        let reopened = try PairedHosts(keychain: disk)
        #expect(reopened.all().isEmpty)
        #expect(reopened.identity.publicKeys == identity)
        #expect(disk.legacy == prior)
    }
    @Test("A read failure or missing identity with existing pairings never mints keys")
    func identityFailure() throws {
        let disk = MemoryHostPersistence()
        disk.legacy = host("Mac")
        disk.identity = nil
        #expect(throws: (any Error).self) { try PairedHosts(keychain: disk) }
        #expect(disk.identity == nil)
        disk.failReads = true
        #expect(throws: (any Error).self) { try PairedHosts(keychain: disk) }
        #expect(disk.identity == nil)
    }
    @Test("Concurrent clients keep both records, and forgetting one touches only its key")
    func scopedWrites() async throws {
        let disk = MemoryHostPersistence()
        let store = try PairedHosts(keychain: disk)
        let a = host("Same Name"), b = host("Same Name")
        let left = HostKeyStore(collection: store, host: nil), right = HostKeyStore(collection: store, host: nil)
        async let one: Void = left.save(a)
        async let two: Void = right.save(b)
        _ = try await (one, two)
        #expect(store.all().count == 2)
        try left.save(nil as PairedHost?)
        #expect(store.all().map(\.host) == [b])
        #expect(throws: (any Error).self) { try right.save(a) }
    }
    @Test("Migration verifies the complete record and survives a lost readback")
    func migrationReadback() throws {
        let disk = MemoryHostPersistence()
        let prior = host("Mac")
        disk.legacy = prior
        let keys = try #require(disk.identity).publicKeys
        disk.corruptWrittenName = true
        #expect(throws: (any Error).self) { try PairedHosts(keychain: disk) }
        #expect(disk.legacy == prior)
        #expect(disk.identity?.publicKeys == keys)
        #expect(disk.pendingMigration)
        disk.corruptWrittenName = false
        let repaired = try PairedHosts(keychain: disk)
        #expect(repaired.all() == [HostPreference(host: prior)])
        #expect(!disk.pendingMigration)
        disk.hosts = nil
        disk.failReadAfterWrite = true
        #expect(throws: (any Error).self) { try PairedHosts(keychain: disk) }
        disk.failReads = false
        disk.failReadAfterWrite = false
        let reopened = try PairedHosts(keychain: disk)
        #expect(reopened.all() == [HostPreference(host: prior)])
        #expect(reopened.identity.publicKeys == keys)
    }
    @Test("A failed collection write does not publish an in-memory pairing")
    func writeFailure() throws {
        let disk = MemoryHostPersistence()
        let store = try PairedHosts(keychain: disk)
        disk.failWrites = true
        #expect(throws: (any Error).self) { try store.set(HostPreference(host: host("Mac"))) }
        #expect(store.all().isEmpty)
    }
}

nonisolated final class MemoryHostPersistence: HostPersistence, @unchecked Sendable {
    var identity: DeviceIdentity? = DeviceIdentity()
    var legacy: PairedHost?
    var hosts: [HostPreference]?
    var pendingMigration = false
    func migrationPending() throws -> Bool { if failReads { throw CocoaError(.fileReadNoPermission) }; return pendingMigration }
    func setMigrationPending(_ pending: Bool) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; pendingMigration = pending }
    var failReads = false
    var failWrites = false
    var corruptWrittenName = false
    var failReadAfterWrite = false
    func loadIdentity() throws -> DeviceIdentity? { if failReads { throw CocoaError(.fileReadNoPermission) }; return identity }
    func save(_ value: DeviceIdentity) throws { identity = value }
    func loadPairedHost() throws -> PairedHost? { legacy }
    func save(_ value: PairedHost?) throws { legacy = value }
    func readHosts() throws -> [HostPreference]? { if failReads { throw CocoaError(.fileReadNoPermission) }; return hosts }
    func writeHosts(_ values: [HostPreference]) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; hosts = values
        if corruptWrittenName, hosts?.isEmpty == false { hosts?[0].alias = "Incorrect alias" }
        if failReadAfterWrite { failReads = true }
    }
}
