import Foundation
import ZephraLinkProtocol
import os

/// The Mac's side of the relay: one socket in a room of its own, one guest at a time.
///
/// A `LinkListener` like the TCP one, so the Mac's session code is the same over either road,
/// but with a limit the local network does not have. The relay gives a host one connection and
/// a frame on it carries no guest id, so two phones at once would be one interleaved stream
/// that no channel could open. The local network is where several phones may connect at once.
///
/// The relay admits one allow-listed guest at a time, so a `joined` while a session is live is
/// never a second phone: it is the announcement of the one already talking, arriving after its
/// first frame because the relay's connection index is eventually consistent. Ending the live
/// session on it would tear down the handshake that frame began, so the session stands until a
/// `left`, or until the road under it goes.
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
            for await event in self.host.peerEvents() { self.peerChanged(event) }
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

    /// Replaces the set of guests the relay will admit into this room, and says whether the room
    /// is open to a guest on no list — which it is exactly while a pairing code is on screen.
    public func updateAllowList(_ keys: [Data], open: Bool = false) async {
        await host.updateAllowList(keys, open: open)
    }

    /// A guest arrived or went.
    ///
    /// A `joined` over a session that is already up is the announcement of that same guest
    /// catching up with its own first frame, so it is left alone.
    private func peerChanged(_ event: RelayPeerEvent) {
        switch event {
        case .joined:
            let opened = openSession()
            if opened.isNew {
                continuation.yield(opened.session)
            } else {
                logger.notice("A guest was announced over the relay after its own first frame.")
            }
        case .left: lock.withLock { defer { session = nil }; return session }?.end(nil)
        }
    }

    /// One frame from whichever guest is in the room.
    ///
    /// A frame with no session behind it opens one: the relay's connection index is eventually
    /// consistent, so a guest's first frame can beat the `peer joined` that announces it, and
    /// dropping that frame would lose a handshake's hello.
    private func deliver(_ frame: Data) {
        let opened = openSession()
        if opened.isNew { continuation.yield(opened.session) }
        opened.session.deliver(frame)
    }

    /// The session up right now, opening one where there is none.
    ///
    /// One take of the lock rather than a read and then a write: the frames pump and the peers
    /// pump are two tasks, and both can find the room empty at the same instant. Whichever makes
    /// the session says so, and only that one is yielded, so the host is never handed two
    /// connections for one guest.
    private func openSession() -> (session: RelayGuestSession, isNew: Bool) {
        lock.withLock {
            if let session { return (session, false) }
            let fresh = RelayGuestSession(host: host)
            session = fresh
            return (fresh, true)
        }
    }

    /// The host's own road stopped, which ends the guest with it.
    ///
    /// Logged with its reason, because from outside this is indistinguishable from a Mac that
    /// simply has no phone: the listener finishes, `RelayRoad` rejoins, and a guest that had
    /// just arrived is left holding a channel to a socket nobody reads.
    private func roadEnded(_ error: Error?) {
        let current = lock.withLock { () -> RelayGuestSession? in
            defer { session = nil }
            return session
        }
        logger.notice(
            "The relay road ended \(error.map { "with \(String(describing: $0))" } ?? "cleanly", privacy: .public), \(current == nil ? "with no guest on it" : "with a guest on it", privacy: .public).")
        current?.end(error)
        continuation.finish()
    }
}
