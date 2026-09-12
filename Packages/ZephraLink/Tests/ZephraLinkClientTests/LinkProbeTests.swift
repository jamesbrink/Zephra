import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// A session that looks live, asked whether it is one.
///
/// The failure behind it: a phone that leaves Wi-Fi mid-session keeps the socket it had. The
/// interface is gone, nothing is delivered, and neither end is told, so the state says live and
/// every request sits for thirty seconds before anybody learns otherwise. A ping costs one
/// frame and settles it.
@MainActor
@Suite("A probe says whether the Mac is still at the other end")
struct LinkProbeTests {
    /// A paired phone with a session already open.
    private func live() async throws -> LinkClientUnderTest {
        let bed = LinkClientUnderTest()
        try await bed.client.pair(with: bed.pairingCode())
        try await settle()
        #expect(bed.client.connection.isLive)
        return bed
    }

    @Test("a probe the Mac answers leaves the session alone")
    func anAnsweredProbeKeepsTheSession() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        await bed.client.probe(timeout: .milliseconds(200))
        #expect(bed.client.connection.isLive)
    }

    @Test("a probe nobody answers ends the session")
    func anUnansweredProbeEndsTheSession() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        bed.host.answersPings = false
        await bed.client.probe(timeout: .milliseconds(50))
        #expect(!bed.client.connection.isLive)
        // A session that ended is a session the reconnection is told about, which is what opens
        // a road to wherever the Mac is now.
        #expect(bed.client.connection.reason != nil)
    }

    @Test("there is nothing to probe with no session, and asking is not an error")
    func probingWithoutASessionDoesNothing() async throws {
        let bed = LinkClientUnderTest()
        await bed.client.probe(timeout: .milliseconds(50))
        #expect(bed.client.connection == .offline)
    }

    /// Lets the frames in flight land: everything here is one process and one actor, so a
    /// couple of turns of the loop is the whole of the wait.
    private func settle() async throws {
        for _ in 0..<8 { await Task.yield() }
    }
}
