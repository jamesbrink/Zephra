import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport
import os

/// The roads a phone reaches this Mac on, opened and closed in one place so the host is handed
/// listeners and never learns what a socket is.
///
/// Two of them. A `TCPListener` on the local network, advertising `_zephra._tcp` with this
/// Mac's room in its TXT record, so a phone that has paired finds it again after the router
/// hands out a different address; and a `RelayRoad` for a phone that is somewhere else, which
/// only exists once the person has allowed access from outside the home network. A session does
/// not know or care which one carried it — the handshake and the channel are the same either
/// way, and the relay copies sealed bytes it has no key to read.
///
/// It remembers the port it actually got, because it may not be the one it asked for: something
/// else on the Mac may hold 7723, and a QR code has to name where the listener really is.
@MainActor
final class CompanionRoads {
    /// The port the local road is on, which is what a pairing code should say.
    private(set) var port = CompanionEndpoints.port

    private var identity: DeviceIdentity?
    private var listeners: [any LinkListener] = []
    private let logger = Logger(subsystem: "io.zephra", category: "companion")

    /// The keys this Mac's roads are opened under. Remembered once, so opening them again when
    /// the preference moves does not have to go back to the keychain.
    func remember(_ identity: DeviceIdentity) {
        self.identity = identity
    }

    /// Opens every road this launch should listen on, closing whatever was open first.
    ///
    /// `allowing` is what the relay admits a guest out of: the paired devices' signing keys, read
    /// afresh every time the host's list moves. The local road needs none — a phone on the same
    /// network is refused by the handshake it cannot complete.
    func open(relay: URL?, allowing: @escaping @MainActor () -> [Data]) async -> [any LinkListener] {
        await close()
        guard let identity else { return [] }
        var roads: [any LinkListener] = []
        if let local = await openLocal(identity: identity) { roads.append(local) }
        if let relay {
            let road = RelayRoad(url: relay, identity: identity, allowed: allowing)
            road.start()
            roads.append(road)
        }
        listeners = roads
        return roads
    }

    /// Closes every road. The host stops its own listeners too; both are idempotent, and
    /// whichever runs first is the one that does the work.
    func close() async {
        let closing = listeners
        listeners = []
        port = CompanionEndpoints.port
        for road in closing { await road.stop() }
    }

    /// The local road, on the port it asked for or on one the system picks when that is taken.
    ///
    /// A Mac whose 7723 is occupied still works: the port it did get goes into the QR code, and
    /// Bonjour carries it to a phone that paired earlier. What it loses is a router rule somebody
    /// wrote by hand, which is a fair trade for starting at all.
    private func openLocal(identity: DeviceIdentity) async -> (any LinkListener)? {
        for wanted in [CompanionEndpoints.port, nil] {
            guard let listener = try? TCPListener(
                port: wanted, advertising: identity.roomID, name: AppSettings.companionName())
            else { continue }
            if let got = try? await listener.start() {
                port = got
                return listener
            }
            await listener.stop()
        }
        logger.error("companion could not listen on the local network")
        return nil
    }
}
