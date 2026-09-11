import Foundation
import ZephraLinkProtocol
import os

/// The Mac's side of the relay: one socket in a room of its own, one guest at a time.
///
/// A `LinkListener` like the TCP one, so the Mac's session code is the same over either road,
/// but with a limit the local network does not have. The relay gives a host one connection and
/// a frame on it carries no guest id, so two phones at once would be one interleaved stream
/// that no channel could open. A `peer joined` ends the session before it and starts a fresh
/// one; the local network is where several phones may connect at once.
public final class RelayListener: LinkListener, @unchecked Sendable {
    private let host: RelayConnection
    private let logger = Logger(subsystem: "io.zephra", category: "link.relay")
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation
    private let lock = NSLock()
    private var session: RelayGuestSession?
    private var pumps: [Task<Void, Never>] = []

    /// A listener in this Mac's own room, which is the hash of its signing key.
    public init(url: URL, identity: DeviceIdentity, session: URLSession = .shared) {
        host = RelayConnection(
            url: url, identity: identity, room: identity.roomID, role: .host, session: session)
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Joins the room and begins waiting for a guest.
    public func start() async throws {
        try await host.start()
        let frames = Task { [weak self] in
            guard let self else { return }
            do {
                for try await frame in self.host.frames() { self.deliver(frame) }
                self.roadEnded(nil)
            } catch {
                self.roadEnded(error)
            }
        }
        let peers = Task { [weak self] in
            guard let self else { return }
            for await event in self.host.peerEvents { self.peerChanged(event) }
        }
        lock.withLock { pumps = [frames, peers] }
    }

    public func connections() -> AsyncStream<any LinkConnection> { stream }

    public func stop() async {
        let running = lock.withLock { () -> ([Task<Void, Never>], RelayGuestSession?) in
            defer { pumps = []; session = nil }
            return (pumps, session)
        }
        running.0.forEach { $0.cancel() }
        running.1?.end(nil)
        await host.close()
        continuation.finish()
    }

    /// A guest arrived or went.
    private func peerChanged(_ event: RelayPeerEvent) {
        switch event {
        case .joined: continuation.yield(beginSession())
        case .left: lock.withLock { defer { session = nil }; return session }?.end(nil)
        }
    }

    /// One frame from whichever guest is in the room.
    ///
    /// A frame with no session behind it opens one: the relay's connection index is eventually
    /// consistent, so a guest's first frame can beat the `peer joined` that announces it, and
    /// dropping that frame would lose a handshake's hello.
    private func deliver(_ frame: Data) {
        let current = lock.withLock { session }
        if let current {
            current.deliver(frame)
        } else {
            let opened = beginSession()
            continuation.yield(opened)
            opened.deliver(frame)
        }
    }

    /// Closes whatever session is up and starts one in its place.
    private func beginSession() -> RelayGuestSession {
        let fresh = RelayGuestSession(host: host)
        let previous = lock.withLock { () -> RelayGuestSession? in
            defer { session = fresh }
            return session
        }
        if previous != nil {
            logger.notice("A second guest joined over the relay; the one before it was closed.")
        }
        previous?.end(nil)
        return fresh
    }

    /// The host's own road stopped, which ends the guest with it.
    private func roadEnded(_ error: Error?) {
        let current = lock.withLock { () -> RelayGuestSession? in
            defer { session = nil }
            return session
        }
        current?.end(error)
        continuation.finish()
    }
}
