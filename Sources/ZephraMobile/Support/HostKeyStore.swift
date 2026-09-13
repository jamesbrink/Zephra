import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

/// A client can only read/write its own pairing. Identity creation is never a client race.
nonisolated final class HostKeyStore: LinkKeyStore, @unchecked Sendable {
    private let collection: PairedHosts
    private let lock = NSLock()
    private var host: PairedHost?
    init(collection: PairedHosts, host: PairedHost?) {
        self.collection = collection; self.host = host
    }
    func loadIdentity() throws -> DeviceIdentity? { collection.identity }
    func save(_ identity: DeviceIdentity) throws {
        guard identity.publicKeys == collection.identity.publicKeys else { throw CocoaError(.fileWriteNoPermission) }
    }
    func loadPairedHost() throws -> PairedHost? { lock.withLock { host } }
    func save(_ host: PairedHost?) throws {
        try lock.withLock {
            if let host {
                let id = HostID(keys: host.keys)
                if let prior = self.host, HostID(keys: prior.keys) != id { throw CocoaError(.fileWriteNoPermission) }
                var record = collection.all().first { $0.id == id } ?? HostPreference(host: host)
                record.host = host
                try collection.set(record)
            } else if let prior = self.host { try collection.remove(HostID(keys: prior.keys)) }
            self.host = host
        }
    }
}
