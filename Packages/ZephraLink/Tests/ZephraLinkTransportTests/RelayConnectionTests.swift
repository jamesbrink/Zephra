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

    @Test("the other end arriving reaches the owner as a peer event")
    func peerEventsSurface() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        try await road.start()
        var events = road.peerEvents.makeAsyncIterator()
        relay.push(.peer(event: .joined))
        #expect(await events.next() == .joined)
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
