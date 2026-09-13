import Foundation
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// A phone that vanished mid-send, and whether the Mac can still close the session it left.
///
/// The failure behind it: a phone walked out of Wi-Fi with a session up. The Mac's writer sat
/// in a send whose completion was never coming, and `close` waited for the writer before it
/// closed the road, so the session, its road and its slot stayed for as long as TCP took to
/// give up — and a revoke or a quit sat behind them.
@MainActor
@Suite("A session whose phone vanished mid-send still closes")
struct CompanionDeadRoadTests {
    @Test("closing a session does not wait on a send that will never complete")
    func closingDoesNotWaitOnAStuckSend() async throws {
        let bed = CompanionTestBed()
        let (macSide, phoneSide) = MemoryLinkConnection.pair()
        let road = StallingConnection(macSide)
        let phone = FakePhone(connection: phoneSide)
        let payload = bed.host.beginPairing()
        bed.listener.offer(road)
        try await phone.connect(to: bed.keys, pairingSecret: payload.secret)
        try await bed.waitUntil { bed.host.sessions.count == 1 }

        // From here every frame the Mac writes sits on the road; the pong to this ping is the
        // send the writer is stuck in when the close arrives.
        road.stallSends()
        try await phone.send(envelope: Envelope(kind: .ping, body: Data("{}".utf8)))
        try await Task.sleep(for: .milliseconds(100))

        var stopped = false
        let stopping = Task { await bed.host.stop(); stopped = true }
        // Polled rather than raced: a structured race over a wait that cannot be cancelled would
        // itself wait forever, which is the failure this pins.
        let deadline = ContinuousClock.now + CompanionSession.drainDeadline + .seconds(2)
        while !stopped, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(stopped, "the host stopped inside the drain deadline plus a moment")
        #expect(bed.host.sessions.isEmpty)
        stopping.cancel()
        await phone.disconnect()
    }
}
