import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkTransport

/// The Mac's side of the relay, which serves every phone in its room and tells them apart by
/// the guest id the relay writes on every frame.
@Suite("A relay listener serves the phones in its room")
struct RelayListenerTests {
    @Test("a guest joining opens a session that carries the room's frames")
    func guestJoiningOpensASession() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined))
        let session = try #require(await connections.next())
        let frames = FrameReader(session.frames())
        try await session.send(Data("sealed".utf8))
        #expect(try await frames.next() == Data("sealed".utf8))
    }

    @Test("a guest leaving ends its session, and the next guest gets a fresh one")
    func leavingEndsTheSession() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined))
        let first = try #require(await connections.next())
        let frames = FrameReader(first.frames())
        relay.push(.peer(event: .left))
        #expect(try await frames.next() == nil)
        relay.push(.peer(event: .joined))
        let second = try #require(await connections.next())
        #expect(ObjectIdentifier(second as AnyObject) != ObjectIdentifier(first as AnyObject))
    }

    @Test("a joined announced after the guest's own first frame leaves that session alone")
    func aLateAnnouncementDoesNotEndTheSession() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        // The relay echoes a `send`, which is a guest's frame arriving before its announcement.
        relay.push(.send(payload: Data("hello".utf8)))
        let session = try #require(await connections.next())
        let frames = FrameReader(session.frames())
        #expect(try await frames.next() == Data("hello".utf8))
        relay.push(.peer(event: .joined))
        relay.push(.send(payload: Data("confirm".utf8)))
        // The same session carries on: a fresh one here would be a handshake torn in half.
        #expect(try await frames.next() == Data("confirm".utf8))
    }

    @Test("the host's socket dying ends the guest's session and the listener with it")
    func aDeadSocketEndsTheSession() async throws {
        let relay = try FakeRelay()
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined))
        let session = try #require(await connections.next())
        let frames = FrameReader(session.frames())
        // The relay drops the socket, which is what it does to a frame past 32 KB. The Mac used
        // to keep this session, answer nothing on it, and rejoin the room beside it.
        relay.stop()
        await #expect(throws: (any Error).self) { try await frames.next() }
        #expect(await connections.next() == nil, "the listener is done with that join")
    }

    @Test("a write that fails takes the road down rather than leaving a session on it")
    func aFailedWriteEndsTheRoad() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let identity = DeviceIdentity()
        let road = RelayConnection(
            url: try await relay.start(), identity: identity, room: identity.roomID, role: .host)
        defer { Task { await road.close() } }
        try await road.start()
        let frames = FrameReader(road.frames())
        road.fail(RelayError.closed)
        await #expect(throws: (any Error).self) { try await frames.next() }
        #expect(road.isClosed)
        await #expect(throws: RelayError.closed) { try await road.send(Data([0x01])) }
    }

    @Test("the allow-list reaches the relay with the join and again when it moves")
    func theAllowListReachesTheRelay() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let phone = DeviceIdentity().publicKeys.signing
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        await listener.updateAllowList([phone])
        try await listener.start()
        #expect(relay.allowList == [phone])
        let second = DeviceIdentity().publicKeys.signing
        await listener.updateAllowList([phone, second])
        try await FakeRelay.waitUntil("the new allow-list") { relay.allowList == [phone, second] }
    }

    @Test("two guests get a session each, and a frame goes to the one the relay named")
    func twoGuestsAreToldApart() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined, from: "G1"))
        let first = try #require(await connections.next())
        relay.push(.peer(event: .joined, from: "G2"))
        let second = try #require(await connections.next())
        #expect(ObjectIdentifier(first as AnyObject) != ObjectIdentifier(second as AnyObject))

        let firstFrames = FrameReader(first.frames())
        let secondFrames = FrameReader(second.frames())
        relay.push(.send(payload: Data("one".utf8), from: "G1"))
        relay.push(.send(payload: Data("two".utf8), from: "G2"))
        #expect(try await firstFrames.next() == Data("one".utf8))
        #expect(try await secondFrames.next() == Data("two".utf8))
    }

    @Test("one guest leaving ends that session and leaves the other phone talking")
    func oneGuestLeavingEndsOneSession() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined, from: "G1"))
        let first = try #require(await connections.next())
        relay.push(.peer(event: .joined, from: "G2"))
        let second = try #require(await connections.next())
        let firstFrames = FrameReader(first.frames())
        let secondFrames = FrameReader(second.frames())

        relay.push(.peer(event: .left, from: "G1"))
        #expect(try await firstFrames.next() == nil)
        relay.push(.send(payload: Data("still here".utf8), from: "G2"))
        #expect(try await secondFrames.next() == Data("still here".utf8))
    }

    @Test("a session writes the guest it belongs to on every frame it sends")
    func aSessionNamesItsGuest() async throws {
        let relay = try FakeRelay()
        defer { relay.stop() }
        let listener = RelayListener(url: try await relay.start(), identity: DeviceIdentity())
        defer { Task { await listener.stop() } }
        try await listener.start()
        var connections = listener.connections().makeAsyncIterator()
        relay.push(.peer(event: .joined, from: "G1"))
        let session = try #require(await connections.next())
        try await session.send(Data("sealed".utf8))
        try await FakeRelay.waitUntil("the frame the session sent") {
            relay.sendTargets == ["G1"]
        }
    }
}