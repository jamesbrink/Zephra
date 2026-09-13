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
        // A reply a hole swallowed is closed by this end's own clock rather than by the gap, so
        // the suite asks the question in milliseconds rather than in the thirty seconds a phone
        // gives a Mac.
        bed.client.requestTimeout = .milliseconds(100)
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        #expect(bed.client.connection == .live(.lan))
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle { bed.client.snapshot != nil }
        // The library pull the snapshot starts is a request and a reply of its own, and a hole
        // now costs the one message it swallowed: a suite that drops "the next frame" has to know
        // which frame that is.
        try await settle { bed.client.libraryIsComplete }
        return bed
    }

    @Test("a delta the road swallows costs one message, not the session")
    func aLostDeltaIsSteppedOver() async throws {
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        // The fresh snapshot says who answered rather than moving the count: a count that moved
        // starts the folder again, which is `LinkLibraryPullTests`' concern, and here the restart
        // would step on the very frame the hole held back. The Mac's folder holds that picture
        // too, so a pull that runs anyway hands back what the phone released rather than nothing.
        world.hostName = Self.answeredTheResync
        bed.host.world = world
        bed.host.library = [ClientFixtures.entry("behind-the-hole.png")]

        bed.road.dropFrame()
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)
        try await bed.host.announce(
            StateDelta.library(.upserted([ClientFixtures.entry("behind-the-hole.png")])),
            kind: .delta)
        try await Self.settle { bed.client.snapshot?.hostName == Self.answeredTheResync }

        #expect(bed.road.dropCount == 1, "the road has to have actually lost one")
        #expect(bed.host.commands.contains(.resync), "the phone asks for the world again")
        #expect(
            bed.client.snapshot?.hostName == Self.answeredTheResync,
            "and the fresh snapshot is what it holds")
        #expect(bed.client.connection == .live(.lan), "a hole is not a reason to drop the link")
        #expect(
            bed.client.library.map(\.fileName) == ["behind-the-hole.png"],
            "the frame waiting behind the hole is released, not thrown away")
    }

    @Test("a chunk the road swallows fails the transfer, and the phone asks once more")
    func aLostChunkIsFetchedAgain() async throws {
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        bed.host.payload = payload

        // The reply and the first chunk go past; the one behind them is lost, and the chunk after
        // *that* arriving out of its turn is what says so.
        bed.road.dropFrame(after: 2)
        async let bytes = bed.client.file(name: "a.png")

        #expect(try await bytes == payload, "the retry is what the caller sees")
        #expect(bed.road.dropCount == 1)
        #expect(bed.host.commands.count >= 2, "the fetch was asked twice")
        #expect(bed.client.connection == .live(.lan))
    }

    @Test("a gap does not throw away a transfer that is still arriving")
    func aGapCostsOnlyWhatItSwallowed() async throws {
        // A hole used to fail every open request and drop every transfer in flight, on the
        // reasoning that it might have been any of them. Over the relay a picture is hundreds of
        // chunks, so a hole lands in the middle of transfers that are still going, and one lost
        // message became five.
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }
        let start = BlobStart(byteCount: 200_000, mime: "image/png")
        bed.client.announce(start)
        bed.client.receive(BlobChunker.chunks(of: Data(count: 200_000), blobID: start.blobID)[0])

        bed.road.dropFrame()
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)
        try await bed.host.announce(LinkReorderingTests.progress(step: 2), kind: .delta)
        try await Self.settle { bed.host.commands.contains(.resync) }

        #expect(bed.road.dropCount == 1, "the road has to have actually lost one")
        #expect(bed.host.commands.contains(.resync), "the world is still asked for")
        #expect(
            bed.client.blobs[start.blobID] != nil,
            "the transfer the hole was not in the middle of is still being assembled")
        #expect(bed.client.blobOrder == [start.blobID])
    }

    @Test("a request whose reply the road swallows is asked again under a fresh id")
    func aLostReplyIsAskedAgain() async throws {
        // The gap no longer closes this: `requestTimeout` does, which is this end's own promise
        // and was always what closed a request the Mac never answered.
        let bed = try await Self.connected()
        defer { Task { await bed.host.stop() } }

        let favourite = Command.setFavourite(names: ["a.png"], on: true)
        bed.road.dropFrame()
        async let done: Void = bed.client.setFavourite(names: ["a.png"], on: true)
        try await Self.settle { bed.host.commands.contains(favourite) }
        // Something has to arrive behind the hole for it to be a hole at all: a gap is only seen
        // when a later frame is waiting on it.
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)

        try await done
        try await Self.settle { bed.host.commands.contains(.resync) }
        #expect(bed.road.dropCount == 1, "the road has to have actually lost the reply")
        #expect(
            bed.host.commands.filter { $0 == .setFavourite(names: ["a.png"], on: true) }.count == 2,
            "the same command, twice")
        #expect(bed.host.commands.contains(.resync), "and the world asked for once")
        #expect(bed.client.connection == .live(.lan))
    }

    /// Waits for the phone to have caught up, or gives up after a couple of seconds.
    /// What the Mac calls itself in the snapshot it answers a resync with, so the suite can see
    /// that snapshot land without moving anything the library reads.
    static let answeredTheResync = "A Mac that answered the resync"

    static func settle(_ until: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if until() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
