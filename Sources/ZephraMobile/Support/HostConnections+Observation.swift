import Foundation
import Observation

extension HostConnections {
    /// Polling is bounded and cancellation-aware; connection recovery itself remains event-driven.
    func observe() async {
        var connected: Set<HostConnection.ID> = []
        while !Task.isCancelled {
            for host in hosts {
                if host.client.pairedHost == nil {
                    await forget(host)
                    continue
                }
                if host.client.connection.isLive {
                    if connected.insert(host.id).inserted, host.client.supportsMultiHost {
                        try? await host.client.setPreviews(host.id == (watched ?? visible?.id))
                    }
                } else { connected.remove(host.id) }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
