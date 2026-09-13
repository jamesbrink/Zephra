import Foundation
import UIKit
import ZephraLinkClient
import ZephraLinkTransport

extension MobileWorkspace {
    static func client(storage: PairedHosts, host: PairedHost?, admission: TransferAdmission, budget: BlobBudget, cadence: RelayCadence, browser: BonjourBrowser) -> LinkClient {
        let roads = NetworkLinkRoads(
            relayURL: URL(string: "wss://zephra-link.urandom.io")!, identity: storage.identity, cadence: cadence, browser: browser)
        return LinkClient(store: HostKeyStore(collection: storage, host: host),
            roads: RelayOnlyRoads.isRequested ? RelayOnlyRoads(roads: roads) : roads,
            deviceName: UIDevice.current.name, transferAdmission: admission, blobBudget: budget)
    }
}
