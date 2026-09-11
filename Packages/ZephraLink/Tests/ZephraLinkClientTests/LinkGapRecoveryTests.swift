import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// A road that loses one frame, which is what a live run through the relay did: the phone held
/// 3, 4 and 5 and frame 2 never came, with nothing logged at either end and the session ending
/// every few seconds until the phone gave up.
@MainActor
@Suite("A phone steps over a lost frame and asks the Mac for the world again")
struct LinkGapRecoveryTests {
    /// A phone past its handshake, with a gap held for milliseconds rather than half a second.
    static func connected() async throws -> LinkClientUnderTest {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        bed.client.frameHold = .milliseconds(30)
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        #expect(bed.client.connection == .live(.lan))
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.snapshot != nil }
        return bed
    }

    @Test("a delta the road swallows costs one message, not the session")
    func aLostDeltaIsSteppedOver() async throws {
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        world.libraryCount = 7
        bed.host.world = world

        bed.road.dropFrame()
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)
        try await bed.host.announce(
            StateDelta.library(.upserted([ClientFixtures.entry("behind-the-hole.png")])),
            kind: .delta)
        try await Self.settle { bed.client.snapshot?.libraryCount == 7 }

        #expect(bed.road.dropCount == 1, "the road has to have actually lost one")
        #expect(bed.host.commands.contains(.resync), "the phone asks for the world again")
        #expect(bed.client.snapshot?.libraryCount == 7, "and the fresh snapshot is what it holds")
        #expect(bed.client.connection == .live(.lan), "a hole is not a reason to drop the link")
        #expect(
            bed.client.library.map(\.fileName) == ["behind-the-hole.png"],
            "the frame waiting behind the hole is released, not thrown away")
    }

    @Test("a chunk the road swallows fails the transfer, and the phone asks once more")
    func aLostChunkIsFetchedAgain() async throws {
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }
        let payload = Data((0..<2048).map { UInt8($0 % 251) })
        bed.host.payload = payload

        // The reply announcing the transfer goes past; the one chunk behind it is lost.
        bed.road.dropFrame(after: 1)
        async let bytes = bed.client.thumbnail(name: "a.png", pixels: 256)
        try await Self.settle { !bed.host.commands.isEmpty }
        // Something has to arrive behind the hole for it to be a hole at all: a gap is only seen
        // when a later frame is waiting on it.
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)

        #expect(try await bytes == payload, "the retry is what the caller sees")
        #expect(bed.road.dropCount == 1)
        #expect(bed.host.commands.count >= 2, "the fetch was asked twice")
        #expect(bed.client.connection == .live(.lan))
    }

    @Test("a request whose reply the road swallows is asked again under a fresh id")
    func aLostReplyIsAskedAgain() async throws {
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }

        bed.road.dropFrame()
        async let done: Void = bed.client.setFavourite(names: ["a.png"], on: true)
        try await Self.settle { !bed.host.commands.isEmpty }
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)

        try await done
        #expect(
            bed.host.commands.filter { $0 == .setFavourite(names: ["a.png"], on: true) }.count == 2,
            "the same command, twice")
        #expect(bed.host.commands.contains(.resync), "and the world asked for once")
        #expect(bed.client.connection == .live(.lan))
    }

    /// Waits for the phone to have caught up, or gives up after a couple of seconds.
    static func settle(_ until: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if until() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
