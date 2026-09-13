import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

extension MobilePreview {
    static var hostCount: Int {
        #if DEBUG
        guard state != nil else { return 1 }
        return min(8, max(1, Int(ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_HOSTS"] ?? "1") ?? 1))
        #else
        return 1
        #endif
    }
    static func addHosts(to hosts: HostConnections, first: LinkClient) {
        guard let firstHost = first.pairedHost else { return }
        hosts.add(HostPreference(host: firstHost), client: first, frozen: true)
        for index in 1..<hostCount {
            guard var snapshot = first.snapshot else { continue }
            if index == 1 { snapshot.multiHost = false } // A mixed-version host remains manual.
            snapshot.hostName = index == 1 ? "Studio Mac" : "Render Mac \(index + 1)"
            let client = LinkClient.frozen(snapshot: snapshot, library: first.library,
                connection: index == hostCount - 1 ? .offline : .live(.relay))
            if let host = client.pairedHost { hosts.add(HostPreference(host: host), client: client, frozen: true) }
        }
    }
    static func offers(for hosts: HostConnections) -> [HostID: HostOffer]? {
        guard state != nil, !hosts.hosts.isEmpty, hosts.hosts.allSatisfy({ $0.reconnect == nil }) else { return nil }
        return Dictionary(uniqueKeysWithValues: hosts.hosts.filter { $0.client.connection.isLive }.map { host in
            (host.id, HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
                executionSeconds: nil, memoryMargin: 10_000_000_000, modelLoaded: true,
                queueCount: 0, queueRevision: "preview", physicalMemory: 32_000_000_000))
        })
    }
}
