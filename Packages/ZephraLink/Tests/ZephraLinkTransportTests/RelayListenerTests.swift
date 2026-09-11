import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkTransport

/// The Mac's side of the relay, which serves one guest at a time and says so.
@Suite("A relay listener serves one guest at a time")
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
        try await waitUntil { relay.allowList == [phone, second] }
    }

    /// Waits for the relay's own timing rather than for a sleep guessed at.
    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return #expect(Bool(false), "the relay never heard the new allow-list")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
