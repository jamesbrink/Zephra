import Foundation
import ZephraLinkProtocol

/// Finding the Mac and opening a road to it, in the order the roads are worth trying.
extension LinkClient {
    /// Connects to the Mac this phone knows, over the best road that answers.
    ///
    /// Idempotent: a second call while one is running does nothing, which is what lets the
    /// interface call it on every foreground without keeping a flag of its own. The local
    /// network first — the stored addresses and a Bonjour browse of the room, dialled together
    /// and the first to open taken (`LocalRoadRace`) — because it is direct and usually right;
    /// the relay after, because it is a hop through somebody else's machine. A refusal ends it
    /// wherever it comes: it is the same Mac at the end of every road.
    public func connect() async {
        guard !isFrozen, !connection.isBusy else { return }
        guard let host = pairedHost else {
            connection = .failed("This device is not paired with a Mac yet.")
            return
        }
        connection = .searching
        var failure: (any Error)?
        let local = await LocalRoadRace(roads: roads).open(
            endpoints: host.endpoints, room: host.roomID, window: Self.lanWindow)
        if let local {
            switch await attempt(.lan, peer: host.keys, secret: nil, open: { local }) {
            case .connected: return
            case .refused(let refusal): return connection = .failed(refusal.reason)
            case .unreachable(let error): failure = error
            }
        }
        guard !Task.isCancelled else { return connection = .offline }
        switch await attempt(.relay, peer: host.keys, secret: nil, open: {
            try await self.roads.connectRelay(room: host.roomID)
        }) {
        case .connected: return
        case .refused(let refusal): connection = .failed(refusal.reason)
        case .unreachable(let error):
            failure = error
            connection = .failed(Self.words(for: failure, host: host.name))
        }
    }

    /// Closes the session and everything waiting on it.
    public func disconnect() async {
        await tearDown()
        connection = .offline
    }

    /// Forgets the Mac altogether: the pairing is gone and a new code is needed to get it back.
    public func forgetHost() async {
        await disconnect()
        try? store.save(nil)
        pairedHost = nil
    }

    /// Opens one road and runs the handshake over it.
    func attempt(
        _ kind: LinkRoad, peer: DevicePublicKeys, secret: Data?,
        open: () async throws -> any LinkConnection
    ) async -> LinkAttempt {
        connection = .connecting(kind)
        do {
            let road = try await open()
            try await openSession(over: road, kind: kind, peer: peer, secret: secret)
            return .connected
        } catch {
            logger.notice("A road did not open: \(String(describing: error), privacy: .public)")
            await tearDown()
            return (error as? LinkError).map(LinkAttempt.refused) ?? .unreachable(error)
        }
    }

    /// Ends the session, if there is one, and fails everything that was waiting on it.
    func tearDown() async {
        guard let session else { return }
        self.session = nil
        preview = nil
        settleEverything(with: LinkClientError.notConnected)
        await session.end(LinkClientError.notConnected)
        sessionEnded()
    }

    /// What to tell the person when no road worked.
    static func words(for failure: (any Error)?, host: String) -> String {
        if let refusal = failure as? LinkError { return refusal.reason }
        return "Zephra could not reach \(host)."
    }
}
