import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport

/// The real roads: Bonjour and TCP on the local network, the relay from anywhere.
///
/// It remembers the hosts a browse turned up, because a `LinkCandidate` carries no endpoint on
/// purpose — the client has no business holding an address, and a Bonjour service is resolved
/// by Network at the moment a connection is made, over whichever interface actually works.
public final class NetworkLinkRoads: LinkRoads, @unchecked Sendable {
    private let relayURL: URL
    private let identity: DeviceIdentity
    private let browser = BonjourBrowser()
    private let lock = NSLock()
    private var seen: [String: DiscoveredHost] = [:]

    /// The roads out of one device, with one relay behind them.
    public init(relayURL: URL, identity: DeviceIdentity) {
        self.relayURL = relayURL
        self.identity = identity
    }

    public func browse() -> AsyncStream<[LinkCandidate]> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return continuation.finish() }
                for await hosts in self.browser.results() {
                    self.remember(hosts)
                    continuation.yield(hosts.map(Self.candidate))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        guard let host = lock.withLock({ seen[candidate.id] }) else {
            throw LinkClientError.unreachable
        }
        return try await browser.connect(host)
    }

    public func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection {
        let road = TCPConnection(host: endpoint.host, port: endpoint.port)
        do {
            try await road.start()
        } catch {
            await road.close()
            throw error
        }
        return road
    }

    /// The relay, whose three refusals of a guest mean three different things to the phone.
    ///
    /// `not allowed` is about this device — the Mac has not paired it, or has revoked it — so it
    /// becomes the `LinkError` a person is shown and the walk of the roads stops. `no host` and
    /// `room busy` are about the moment: the Mac is asleep, or its one guest slot is still held
    /// by a session that has not finished going. Those read as unreachable, which is what the
    /// caller waits on `LinkBackoff` and tries again after.
    public func connectRelay(room: RoomID) async throws -> any LinkConnection {
        let road = RelayConnection(url: relayURL, identity: identity, room: room, role: .guest)
        do {
            try await road.start()
        } catch {
            await road.close()
            guard let refusal = error as? RelayError else { throw error }
            if let shown = refusal.refusalToShow { throw shown }
            throw refusal.isTemporary ? LinkClientError.unreachable : refusal
        }
        return road
    }

    /// Stops browsing, which the phone does when it leaves the screen that lists Macs.
    public func stopBrowsing() { browser.stop() }

    private func remember(_ hosts: [DiscoveredHost]) {
        lock.withLock {
            for host in hosts { seen[host.id] = host }
        }
    }

    private static func candidate(_ host: DiscoveredHost) -> LinkCandidate {
        LinkCandidate(id: host.id, name: host.name, roomID: host.roomID)
    }
}
