import Foundation
import ZephraLinkProtocol

/// The first connection to a Mac, which is the only one that carries a secret.
extension LinkClient {
    /// Pairs with the Mac a scanned code names, and stays connected to it.
    ///
    /// The code's own addresses and a Bonjour browse of its room first, dialled together and
    /// the first to open taken, then the relay: a phone in the same room as the Mac should not
    /// have to reach the internet to pair with it, and a phone that is not should still be able
    /// to, and neither should wait on an address the other cannot see. The secret rides in the
    /// handshake's key schedule as its salt, so a device that did not read the code derives
    /// different keys and fails at the first tag — a refusal with words for a person, not a
    /// frame that will not decrypt.
    public func pair(with payload: PairingPayload) async throws {
        guard !isFrozen else { return }
        farewell = nil
        await disconnect()
        guard !payload.isExpired() else {
            throw LinkError(
                code: .refused, reason: "That pairing code has expired. Show a new one on the Mac.")
        }
        var failure: (any Error)?
        connection = .searching
        let local = await LocalRoadRace(roads: roads).open(
            endpoints: payload.endpoints, room: payload.roomID, window: Self.lanWindow)
        if let local {
            switch await attempt(.lan, peer: payload.keys, secret: payload.secret, open: { local }) {
            case .connected: return remember(payload)
            case .refused(let refusal): throw refused(refusal)
            case .unreachable(let error): failure = error
            }
        }
        switch await attempt(.relay, peer: payload.keys, secret: payload.secret, open: {
            try await self.roads.connectRelay(room: payload.roomID)
        }) {
        case .connected: return remember(payload)
        case .refused(let refusal): throw refused(refusal)
        case .unreachable(let error): failure = error
        }
        connection = .failed(Self.words(for: failure, host: payload.hostName))
        throw failure ?? LinkClientError.unreachable
    }

    /// Keeps the Mac a successful pairing named.
    private func remember(_ payload: PairingPayload) {
        let host = PairedHost(payload)
        try? store.save(host)
        pairedHost = host
    }

    /// A refusal, shown and thrown: the person is owed the Mac's own sentence.
    ///
    /// The Mac answers a device it will not talk to with one sentence, the same one whether the
    /// key is unknown or the code has come down — deliberately, so an unpaired peer learns
    /// nothing else. On the pairing screen that sentence is true and not much use, so the thing
    /// to check is added to it here, where we know a code was being read.
    private func refused(_ refusal: LinkError) -> LinkError {
        let shown = refusal.code == .notPaired
            ? LinkError(
                code: .notPaired,
                reason: "\(refusal.reason) Check that the code is still showing on your Mac.")
            : refusal
        connection = .failed(shown.reason)
        return shown
    }
}
