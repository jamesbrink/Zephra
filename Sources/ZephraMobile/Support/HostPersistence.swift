import ZephraLinkClient
import ZephraLinkProtocol

/// Keychain operations exposed narrowly so migration and failure handling are testable.
nonisolated protocol HostPersistence: LinkKeyStore {
    func readHosts() throws -> [HostPreference]?
    func writeHosts(_ hosts: [HostPreference]) throws
}
