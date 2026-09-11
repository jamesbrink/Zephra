import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkTransport

/// The join sequence against a relay in the process, signature and all.
@Suite("A relay road joins a room and carries frames")
struct RelayConnectionTests {
    @Test("a host signs the challenge and is let into its own room")
    func joinsAsHost() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        try await road.start()
        #expect(relay.joinedRoom == identity.roomID)
    }

    @Test("a refusal carries the relay's own reason")
    func refusalCarriesTheReason() async throws {
        let relay = try FakeRelay(refusing: "challenge expired")
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        await #expect(throws: RelayError.refused("challenge expired")) { try await road.start() }
    }

    @Test("a sealed frame goes out and the room's answer comes back as bytes")
    func framesCross() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        let frames = FrameReader(road.frames())
        let payload = Data((0..<2048).map { UInt8($0 % 251) })
        try await road.send(payload)
        #expect(try await frames.next() == payload)
    }

    @Test("a payload past one frame is cut up on the way out and whole on the way in")
    func aLargePayloadCrossesInSlices() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        let frames = FrameReader(road.frames())
        // A sealed 64 KiB blob chunk, which is what closed the socket before it was cut up:
        // base64 of it is about 87 KB and API Gateway allows 32 KB in one frame.
        let payload = Data((0..<(64 * 1024 + 25)).map { UInt8($0 % 251) })
        try await road.send(payload)
        #expect(try await frames.next() == payload)
        let sizes = relay.sendFrameSizes
        #expect(sizes.count == 4, "one frame each for four slices")
        #expect(sizes.allSatisfy { $0 < 32_000 }, "every frame is inside the relay's own limit")
    }

    @Test("the other end arriving reaches the owner as a peer event")
    func peerEventsSurface() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        try await road.start()
        var events = road.peerEvents().makeAsyncIterator()
        relay.push(.peer(event: .joined))
        #expect(await events.next() == .joined)
    }

    @Test("the relay's three refusals of a guest are told apart")
    func refusalsAreToldApart() {
        // `not allowed` is about this device and is the sentence a person is shown; the other two
        // are about the moment and are worth another attempt after a wait.
        #expect(RelayError.refused("not allowed").refusalToShow == LinkError.notPaired)
        #expect(!RelayError.refused("not allowed").isTemporary)
        #expect(RelayError.refused("no host").isTemporary)
        #expect(RelayError.refused("room busy").isTemporary)
        #expect(RelayError.refused("no host").refusalToShow == nil)
        #expect(RelayError.refused("room busy").refusalToShow == nil)
        #expect(!RelayError.refused("bad signature").isTemporary)
        #expect(RelayError.refused("bad signature").refusalToShow == nil)
        #expect(!RelayError.closed.isTemporary)
    }

    @Test("a guest sends no allow-list, whatever it is told to admit")
    func aGuestSendsNoAllowList() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        await road.updateAllowList([Data(repeating: 4, count: 32)])
        try await road.start()
        #expect(relay.allowList == nil)
    }

    @Test("a room open for a pairing says so in the join, and shuts on the next word")
    func anOpenRoomIsDeclaredInTheJoin() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        await road.updateAllowList([], open: true)
        try await road.start()
        #expect(relay.isRoomOpen, "a first pairing has no key on any list")

        await road.updateAllowList([Data(repeating: 4, count: 32)], open: false)
        try await waitUntil { !relay.isRoomOpen }
        #expect(relay.allowList == [Data(repeating: 4, count: 32)])
    }

    /// Waits for the relay to have heard what the road said, or gives up after a second.
    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("the relay never heard it")
    }

    @Test("a refusal after the join reaches the road's owner and leaves the road open")
    func relayErrorsSurface() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        var refusals = road.relayErrors().makeAsyncIterator()
        let frames = FrameReader(road.frames())

        relay.push(.error(reason: "bad payload"))
        #expect(await refusals.next() == "bad payload", "the relay's own word, not ours")

        // The frame that caused it is gone — that is a gap for the far end to step over — but
        // the road is not: the relay leaves a joined connection open after an error, and so does
        // this end.
        let payload = Data([0x01, 0x02, 0x03])
        try await road.send(payload)
        #expect(try await frames.next() == payload, "the road still carries")
    }

    @Test("a write into a dead socket fails loudly rather than being swallowed")
    func aFailedWriteEndsTheRoad() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        let frames = FrameReader(road.frames())

        // The socket goes without this end saying so, which is the shape a write failure takes.
        road.task.cancel(with: .goingAway, reason: nil)
        await #expect(throws: (any Error).self) { try await road.send(Data([0x09])) }
        await #expect(throws: (any Error).self) { _ = try await frames.next() }
        #expect(road.isClosed, "a road that cannot write is a road nothing may wait on")
    }

    @Test("a frame before the room is joined is refused rather than sent")
    func sendBeforeJoin() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        await #expect(throws: RelayError.closed) { try await road.send(Data([0x01])) }
    }
}
