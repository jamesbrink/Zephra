import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// Every way a session dies under the phone, and how quickly the phone notices.
///
/// The failure this is about is a Mac whose relay socket went while the phone's did not: the
/// room was empty, the Mac had rejoined it with a new socket, and the phone sat on a live-looking
/// session where every request timed out. What the phone hears is a `peer left` or a send that
/// fails, and either ends the session so the reconnection can open a road to the new join.
@MainActor
@Suite("A session over a dead road ends, and says so at once")
struct LinkSessionDeathTests {
    /// A paired phone with a session already open.
    private func live() async throws -> LinkClientUnderTest {
        let bed = LinkClientUnderTest()
        try await bed.client.pair(with: bed.pairingCode())
        try await settle()
        #expect(bed.client.connection.isLive)
        return bed
    }

    @Test("the Mac leaving the room ends the session")
    func peerLeftEndsTheSession() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        bed.road.announce(.left)
        try await settle()
        #expect(!bed.client.connection.isLive)
        #expect(bed.client.connection == .offline)
    }

    @Test("the Mac joining the room leaves a live session alone")
    func peerJoinedLeavesItAlone() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        bed.road.announce(.joined)
        try await settle()
        #expect(bed.client.connection.isLive)
    }

    @Test("a send that fails ends the session rather than reporting nothing")
    func aFailedSendEndsTheSession() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        bed.road.refuseSends()
        try? await bed.client.cancel()
        try await settle()
        #expect(!bed.client.connection.isLive)
    }

    @Test("the end of a session is announced, so a reconnection starts without waiting")
    func theEndIsAnnounced() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        let endings = bed.client.sessionEndings()
        let waiting = Task.detached { await endings.first { _ in true } }
        bed.road.announce(.left)
        // No poll and no sleep: the ending arrives because the session ended.
        #expect(await waiting.value != nil)
    }

    @Test("a send stuck on a dead road does not keep the session from ending")
    func aStuckSendDoesNotHoldTheEnding() async throws {
        let bed = try await live()
        defer { Task { await bed.host.stop() } }
        // The road is the one a phone that walked out of Wi-Fi holds: the interface is gone, a
        // send sits forever, and nothing completes it but closing the road. The probe's ping is
        // that send, and the probe's timeout is what ends the session behind it.
        bed.road.stallSends()
        let probing = Task { await bed.client.probe(timeout: .milliseconds(50)) }
        // Polled rather than raced: a structured race over a wait that cannot be cancelled would
        // itself wait forever, which is the failure this pins.
        for _ in 0..<40 where bed.client.connection.isLive {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!bed.client.connection.isLive, "the session ended within two seconds")
        probing.cancel()
    }

    /// Lets the frames in flight land: everything here is one process and one actor, so a
    /// couple of turns of the loop is the whole of the wait.
    private func settle() async throws {
        for _ in 0..<8 { await Task.yield() }
    }
}
