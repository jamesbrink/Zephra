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

    @Test("slices leave at the road's cadence rather than as fast as the socket takes them")
    func slicesArePaced() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        // A hundred a second with two in hand, so six slices are four waits of ten milliseconds
        // each rather than the seconds a real road's rate would cost.
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest,
            cadence: RelayCadence(messagesPerSecond: 100, burst: 2))
        defer { Task { await road.close() } }
        try await road.start()
        let frames = FrameReader(road.frames())

        let payload = Data((0..<(RelayFragment.byteLimit * 5 + 1)).map { UInt8($0 % 251) })
        try await road.send(payload)
        #expect(try await frames.next() == payload, "and the whole of it still arrives")

        let arrivals = relay.sendArrivals
        #expect(arrivals.count == 6, "six slices")
        guard let first = arrivals.first, let last = arrivals.last else { return }
        // Four of the six had to wait for a token; at a hundred a second that is 40 ms.
        #expect(last - first >= .milliseconds(25), "the tail of a transfer waited its turn")
    }

    @Test("a lossy, reordering relay costs the frames it swallowed and nothing else")
    func aLossyRelayDoesNotEndTheRoad() async throws {
        // The relay as it behaves under load: one invocation per frame, posting concurrently, and
        // now and then one that never forwards. Nothing above the road may be asked to survive
        // this until the road itself does.
        let relay = try FakeRelay(
            dropEvery: 37, forwardJitter: .milliseconds(0)...(.milliseconds(40)))
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()

        // Two megabytes as the chunks a picture crosses in: 64 KiB each, six slices each.
        let chunks = (0..<32).map { index in
            Data((0..<(64 * 1024)).map { UInt8(($0 &+ index) % 251) })
        }
        let stream = road.frames()
        let received = Task { () -> [Data] in
            var seen: [Data] = []
            guard
                (try? await {
                    for try await bytes in stream {
                        seen.append(bytes)
                        if seen.count == chunks.count { return }
                    }
                }()) != nil
            else { return seen }
            return seen
        }
        for chunk in chunks { try await road.send(chunk) }
        // Long enough for the jitter to have delivered everything it is going to.
        try await Task.sleep(for: .milliseconds(600))
        received.cancel()
        let arrived = await received.value

        #expect(relay.dropCount > 0, "the relay has to have actually lost some")
        #expect(!road.isClosed, "lost slices are lost frames, not a lost road")
        #expect(!arrived.isEmpty, "and most of the picture still crosses")
        #expect(
            arrived.allSatisfy { chunks.contains($0) },
            "every frame that arrived is one that was sent, whole")
    }

    @Test("a host writes the guest a frame is for on every slice of it")
    func aHostNamesTheGuestItIsWritingTo() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        try await road.start()
        // Big enough to be cut up: every slice has to name the same phone, or half a sealed
        // frame lands on one and half on nobody.
        let payload = Data((0..<(64 * 1024 + 25)).map { UInt8($0 % 251) })
        try await road.send(payload, to: "G1")
        try await FakeRelay.waitUntil("four slices") { relay.sendTargets.count == 4 }
        #expect(relay.sendTargets.allSatisfy { $0 == "G1" }, "\(relay.sendTargets)")
    }

    @Test("a phone names no guest, since it has one peer")
    func aGuestNamesNobody() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        try await road.send(Data("sealed".utf8))
        try await FakeRelay.waitUntil("the phone's frame") { relay.sendTargets.count == 1 }
        #expect(relay.sendTargets == [nil])
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

    @Test("the gateway's own answer is carried up as a road error and leaves the road open")
    func aForeignMessageIsNotFatal() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .guest)
        defer { Task { await road.close() } }
        try await road.start()
        var refusals = road.relayErrors().makeAsyncIterator()
        let frames = FrameReader(road.frames())

        relay.push(.foreign(message: "Internal server error"))
        #expect(await refusals.next() == "Internal server error", "the gateway's own words")

        // The frame that drew it is gone — a gap for the far end to step over — but the road is
        // not: failing to decode this used to end the session over one gateway hiccup.
        let payload = Data([0x01, 0x02, 0x03])
        try await road.send(payload)
        #expect(try await frames.next() == payload, "the road still carries")
        #expect(!road.isClosed)
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
