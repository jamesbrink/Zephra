import Foundation
import Observation
import ZephraLinkClient
import ZephraLinkProtocol

/// Independent clients; the watched host is presentation state, never a mutation destination.
@MainActor @Observable
final class HostConnections {
    private(set) var hosts: [HostConnection] = []
    var watched: HostID?
    var isAdding = false
    var failure: String?
    var isActive = false
    var pairing: LinkClient
    var isPairing = false
    let catalog: LibraryCatalog
    @ObservationIgnored let storage: PairedHosts?
    @ObservationIgnored let makeClient: (PairedHost?) -> LinkClient
    @ObservationIgnored let pathWatch = HostsPathWatch()
    var visible: HostConnection? { hosts.first { $0.id == watched } ?? hosts.first }
    var client: LinkClient { visible?.client ?? pairing }

    init(storage: PairedHosts?, catalog: LibraryCatalog, makeClient: @escaping (PairedHost?) -> LinkClient) {
        self.storage = storage; self.catalog = catalog; self.makeClient = makeClient
        pairing = makeClient(nil)
        for preference in storage?.all() ?? [] { add(preference, client: makeClient(preference.host)) }
    }
    func add(_ preference: HostPreference, client: LinkClient, frozen: Bool = false) {
        guard !hosts.contains(where: { $0.id == preference.id }) else { return }
        let library = catalog.addHost(preference.id, client: client, frozen: frozen)
        let host = HostConnection(preference: preference, client: client, catalog: library, frozen: frozen)
        hosts.append(host)
        if watched == nil { watched = host.id }
        if isActive && preference.enabled { host.reconnect?.begin() }
    }
    func pair(_ payload: PairingPayload) async throws {
        guard !isPairing else { return }
        isPairing = true
        defer { isPairing = false }
        let id = HostID(keys: payload.keys)
        let existing = hosts.first { $0.id == id }
        guard existing != nil || hosts.filter({ $0.preference.enabled }).count < 8 else {
            throw LinkError(code: .refused, reason: "Disable a Mac before adding another. Up to eight can connect at once.")
        }
        let client = existing?.client ?? makeClient(nil)
        pairing = client
        await existing?.reconnect?.stopAndDrain()
        do { try await client.pair(with: payload) }
        catch {
            await client.disconnect()
            if isActive && existing?.preference.enabled == true { existing?.reconnect?.begin() }
            throw error
        }
        guard let host = client.pairedHost else { return }
        if let existing {
            var preference = existing.preference
            preference.host = host
            update(preference)
        } else { add(HostPreference(host: host), client: client) }
        watched = id
        pairing = makeClient(nil)
        isAdding = false
    }
    func setActive(_ active: Bool) {
        isActive = active
        if active { pathWatch.start(self) } else { pathWatch.stop() }
        for host in hosts {
            if active && host.preference.enabled { host.reconnect?.begin() }
            else { host.reconnect?.end() }
        }
    }
    func update(_ preference: HostPreference) {
        do {
            if preference.enabled && hosts.filter({ $0.preference.enabled && $0.id != preference.id }).count >= 8 {
                throw LinkError(code: .refused, reason: "Enable up to eight Macs at a time.")
            }
            try storage?.set(preference)
            hosts.first { $0.id == preference.id }?.preference = preference
            setActive(isActive)
        } catch { failure = error.localizedDescription }
    }
    func forget(_ host: HostConnection) async {
        do {
            try storage?.remove(host.id)
            await host.reconnect?.stopAndDrain()
            await host.client.disconnect()
            await catalog.removeHost(host.id)
            hosts.removeAll { $0.id == host.id }
            if watched == host.id { watched = hosts.first?.id }
        } catch { failure = error.localizedDescription }
    }
    func watch(_ id: HostID) {
        watched = id
        for host in hosts where host.client.supportsMultiHost {
            Task { try? await host.client.setPreviews(host.id == id) }
        }
    }
}
