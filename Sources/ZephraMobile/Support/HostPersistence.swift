import ZephraLinkClient
import ZephraLinkProtocol

/// Keychain operations exposed narrowly so migration and failure handling are testable.
nonisolated protocol HostPersistence: LinkKeyStore {
    func migrationPending() throws -> Bool
    func setMigrationPending(_ pending: Bool) throws
    func readHosts() throws -> [HostPreference]?
    func writeHosts(_ hosts: [HostPreference]) throws
}
