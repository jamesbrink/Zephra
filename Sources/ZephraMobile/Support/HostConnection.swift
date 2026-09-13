import Foundation
import Observation
import ZephraLinkClient
import ZephraLinkProtocol

@MainActor @Observable
final class HostConnection: Identifiable {
    var preference: HostPreference
    let client: LinkClient
    let reconnect: LinkReconnect?
    let catalog: LibraryCatalog
    var id: HostID { preference.id }
    var name: String { preference.name }
    init(preference: HostPreference, client: LinkClient, catalog: LibraryCatalog, frozen: Bool = false) {
        self.preference = preference; self.client = client; self.catalog = catalog
        reconnect = frozen ? nil : LinkReconnect(client: client)
    }
}
