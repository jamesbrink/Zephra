import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

extension HostConnections {
    func performPair(_ payload: PairingPayload) async throws {
        let id = HostID(keys: payload.keys)
        let existing = hosts.first { $0.id == id }
        guard existing != nil || hosts.filter({ $0.preference.enabled }).count < 8 else {
            throw LinkError(code: .refused, reason: "Disable a Mac before adding another. Up to eight can connect at once.")
        }
        let client = existing?.client ?? makeClient(nil)
        pairing = client
        await existing?.reconnect?.stopAndDrain()
        do { try await client.pair(with: payload); try Task.checkCancellation() }
        catch {
            await client.disconnect()
            if isActive && existing?.preference.enabled == true { existing?.reconnect?.begin() }
            if Task.isCancelled { throw CancellationError() }
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
}
