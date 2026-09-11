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
}
