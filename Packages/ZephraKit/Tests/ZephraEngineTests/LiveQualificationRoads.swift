import Foundation
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraLinkTransport

/// Opt-in qualification uses actual sockets but cannot discover or dial a user's Mac.
struct LiveQualificationRoads: LinkRoads {
    let endpoint: Endpoint?
    let network: NetworkLinkRoads
    func browse() -> AsyncStream<[LinkCandidate]> { AsyncStream { $0.finish() } }
    func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }
    func connectLAN(_ ignored: Endpoint) async throws -> any LinkConnection {
        guard let endpoint else { throw LinkClientError.unreachable }
        return try await network.connectLAN(endpoint)
    }
    func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection {
        guard endpoint == nil else { throw LinkClientError.unreachable }
        return try await network.connectRelay(room: room, pairing: pairing)
    }
}
