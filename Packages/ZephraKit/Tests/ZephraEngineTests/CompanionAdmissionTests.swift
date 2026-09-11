import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraEngine
@testable import ZephraLinkHost

/// What a connection that says nothing costs the Mac, which is what an unpaired device can do.
@MainActor
@Suite("A connection that has not finished its handshake is held on a short leash")
struct CompanionAdmissionTests {
    @Test("no more than eight connections may sit in the plaintext stage")
    func theUnauthenticatedAreCapped() async throws {
        let bed = CompanionTestBed()
        bed.host.handshakeDeadline = .seconds(30)
        var ends: [MemoryLinkConnection] = []
        for _ in 0..<CompanionHost.unauthenticatedLimit {
            let (macSide, mine) = MemoryLinkConnection.pair()
            ends.append(mine)
            bed.listener.offer(macSide)
        }
        try await bed.waitUntil { bed.host.sessions.count == CompanionHost.unauthenticatedLimit }

        let (refusedSide, refused) = MemoryLinkConnection.pair()
        bed.listener.offer(refusedSide)
        // The ninth is closed rather than given a session, and the far end sees the road go.
        var frames = refused.frames().makeAsyncIterator()
        #expect(try await frames.next() == nil)
        #expect(bed.host.sessions.count == CompanionHost.unauthenticatedLimit)
        #expect(bed.host.unauthenticatedCount == CompanionHost.unauthenticatedLimit)
        await bed.shutdown()
    }

    @Test("a paired phone still gets in while eight strangers are knocking")
    func theCapCountsOnlyTheUnauthenticated() async throws {
        let bed = CompanionTestBed()
        bed.host.handshakeDeadline = .seconds(30)
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        #expect(bed.host.unauthenticatedCount == 0, "a phone past its handshake is not counted")

        var ends: [MemoryLinkConnection] = []
        for _ in 0..<CompanionHost.unauthenticatedLimit {
            let (macSide, mine) = MemoryLinkConnection.pair()
            ends.append(mine)
            bed.listener.offer(macSide)
        }
        try await bed.waitUntil {
            bed.host.sessions.count == CompanionHost.unauthenticatedLimit + 1
        }
        await bed.shutdown()
    }

    @Test("a connection that never says hello is closed once its time is up")
    func silenceIsClosedOut() async throws {
        let bed = CompanionTestBed()
        bed.host.handshakeDeadline = .milliseconds(20)
        let (macSide, mine) = MemoryLinkConnection.pair()
        bed.listener.offer(macSide)
        try await bed.waitUntil { bed.host.sessions.count == 1 }

        var frames = mine.frames().makeAsyncIterator()
        #expect(try await frames.next() == nil, "the road goes when the clock runs out")
        try await bed.waitUntil { bed.host.sessions.isEmpty }
        await bed.shutdown()
    }

    @Test("a phone that finishes its handshake is not closed out by that clock")
    func aFinishedHandshakeStopsTheClock() async throws {
        let bed = CompanionTestBed()
        bed.host.handshakeDeadline = .milliseconds(20)
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        try await Task.sleep(for: .milliseconds(60))

        #expect(bed.host.sessions.count == 1)
        #expect(bed.host.sessions.first?.isReady == true)
        await bed.shutdown()
    }
}
