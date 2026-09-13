import Foundation
import Observation

extension HostConnections {
    /// Each live session gets its own short attempt; a silent host cannot hold up the rest.
    func observe() async {
        var connected: [HostConnection.ID: (session: UUID, enabled: Bool)] = [:]
        while !Task.isCancelled {
            var changes: [(HostConnection, UUID, Bool)] = []
            for host in hosts {
                if host.client.pairedHost == nil {
                    await forget(host)
                    connected[host.id] = nil
                    continue
                }
                if host.client.supportsMultiHost, let session = host.client.authenticatedSessionID {
                    let enabled = host.id == (watched ?? visible?.id)
                    if connected[host.id]?.session != session || connected[host.id]?.enabled != enabled {
                        changes.append((host, session, enabled))
                    }
                } else { connected[host.id] = nil }
            }
            await withTaskGroup(of: (HostConnection.ID, UUID, Bool)?.self) { group in
                for (host, session, enabled) in changes {
                    let client = host.client, id = host.id
                    group.addTask {
                        do {
                            try await client.setPreviews(enabled)
                            return (id, session, enabled)
                        } catch { return nil }
                    }
                }
                for await result in group {
                    guard let (id, session, enabled) = result,
                          hosts.first(where: { $0.id == id })?.client.authenticatedSessionID == session,
                          enabled == (id == (watched ?? visible?.id)) else { continue }
                    connected[id] = (session, enabled)
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
