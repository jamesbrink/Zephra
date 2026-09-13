import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

/// Serializes collection writes and resolves the phone identity exactly once.
nonisolated final class PairedHosts: @unchecked Sendable {
    let identity: DeviceIdentity
    private let keychain: any HostPersistence
    private let lock = NSLock()
    private var records: [HostPreference]

    init(keychain: any HostPersistence = MobileKeychain()) throws {
        self.keychain = keychain
        let pending = try keychain.migrationPending()
        let saved = pending ? nil : try keychain.readHosts()
        let legacy = saved == nil ? try keychain.loadPairedHost() : nil
        if let identity = try keychain.loadIdentity() { self.identity = identity }
        else {
            guard (saved ?? []).isEmpty && legacy == nil else { throw CocoaError(.fileReadCorruptFile) }
            let identity = DeviceIdentity()
            try keychain.save(identity)
            self.identity = identity
        }
        if let saved {
            records = saved
        } else {
            records = legacy.map { [HostPreference(host: $0)] } ?? []
            try keychain.setMigrationPending(true)
            try keychain.writeHosts(records)
            guard try keychain.readHosts() == records else {
                throw CocoaError(.fileWriteUnknown)
            }
            try keychain.setMigrationPending(false)
        }
    }
    func all() -> [HostPreference] { lock.withLock { records } }
    func set(_ record: HostPreference) throws {
        try lock.withLock {
            var next = records.filter { $0.id != record.id }
            next.append(record)
            try keychain.writeHosts(next)
            records = next
        }
    }
    func remove(_ id: HostID) throws {
        try lock.withLock {
            let next = records.filter { $0.id != id }
            try keychain.writeHosts(next)
            records = next
        }
    }
}
