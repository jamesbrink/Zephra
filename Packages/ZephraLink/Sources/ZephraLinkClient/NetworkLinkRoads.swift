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
    private let cadence: RelayCadence
    private let browser: BonjourBrowser
    private let lock = NSLock()
    private var seen: [String: DiscoveredHost] = [:]

    /// The roads out of one device, with one relay behind them.
    public init(relayURL: URL, identity: DeviceIdentity, cadence: RelayCadence? = nil, browser: BonjourBrowser? = nil) {
        self.browser = browser ?? BonjourBrowser()
        self.cadence = cadence ?? RelayCadence(messagesPerSecond: 120, burst: 40)
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

    /// The relay, whose three refusals of a guest mean four different things to the phone.
    ///
    /// `no host` and `room full` are about the moment: the Mac is asleep, or its room already
    /// holds as many phones as it may, some of them perhaps sessions that have not finished
    /// going. Those read as unreachable, which is what the caller waits on `LinkBackoff` and
    /// tries again after.
    ///
    /// `not allowed` is about this device, and what it is worth depends on what the phone is
    /// doing. Reading a code, it is the refusal a person is owed and the walk of the roads stops.
    /// Reconnecting, it is `notAdmitted` and the phone waits: the list the relay read is the Mac's
    /// and the Mac may only just have joined its room — its own allow-list arrives in the join or
    /// a moment behind it — so a refusal here is a list a beat out of date and not a pairing
    /// withdrawn. Only the Mac's own handshake may say that.
    public func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection {
        let road = RelayConnection(url: relayURL, identity: identity, room: room, role: .guest, cadence: cadence)
        do {
            try await road.start()
        } catch {
            await road.close()
            guard let refusal = error as? RelayError else { throw error }
            throw Self.failure(for: refusal, pairing: pairing)
        }
        return road
    }

    /// What one of the relay's refusals is to the phone, given what the phone was doing.
    static func failure(for refusal: RelayError, pairing: Bool) -> any Error {
        if let shown = refusal.refusalToShow { return pairing ? shown : LinkClientError.notAdmitted }
        return refusal.isTemporary ? LinkClientError.unreachable : refusal
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
