import Foundation
import ZephraLinkProtocol
import os

/// The Mac's side of the relay: one socket in a room of its own, and a session for every phone
/// in it.
///
/// A `LinkListener` like the TCP one, so the Mac's session code is the same over either road.
/// The relay gives a host one connection for all of its guests, so every frame that crosses it
/// names the phone it belongs to — the relay writes `from` on what arrives here and this writes
/// `to` on what leaves — and the routing is what `RelayListener+Guests` does. A relay that names
/// nobody is the build before the room held several, and its one guest is whichever session is
/// up, which is how an older relay keeps working unchanged.
///
/// A `joined` for a guest already talking is that phone's announcement arriving after its own
/// first frame, because the relay's connection index is eventually consistent. Ending the live
/// session on it would tear down the handshake that frame began, so the session stands until a
/// `left` naming it, or until the road under it goes.
public final class RelayListener: LinkListener, @unchecked Sendable {
    /// The key a guest the relay did not name is filed under. No connection id is empty, so
    /// nothing else can land on it.
    static let anonymousGuest = ""

    let host: RelayConnection
    let logger = Logger(subsystem: "io.zephra", category: "link.relay")
    let continuation: AsyncStream<any LinkConnection>.Continuation
    let lock = NSLock()
    /// One session per guest, by the relay's connection id for it.
    var guests: [String: RelayGuestSession] = [:]
    private let stream: AsyncStream<any LinkConnection>
    private var pump: Task<Void, Never>?

    /// A listener in this Mac's own room, which is the hash of its signing key.
    public init(url: URL, identity: DeviceIdentity, session: URLSession = .shared) {
        host = RelayConnection(
            url: url, identity: identity, room: identity.roomID, role: .host, session: session)
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Joins the room and begins waiting for guests.
    ///
    /// One pump rather than one for frames and one for peer notices: a `left` that overtook the
    /// frames behind it would end a session still being read from.
    public func start() async throws {
        try await host.start()
        let pump = Task { [weak self] in
            guard let self else { return }
            do {
                for try await signal in self.host.guestSignals() { self.received(signal) }
                self.roadEnded(nil)
            } catch {
                self.roadEnded(error)
            }
        }
        lock.withLock { self.pump = pump }
    }

    public func connections() -> AsyncStream<any LinkConnection> { stream }

    public func stop() async {
        let running = lock.withLock { () -> (Task<Void, Never>?, [RelayGuestSession]) in
            defer { pump = nil; guests = [:] }
            return (pump, Array(guests.values))
        }
        running.0?.cancel()
        running.1.forEach { $0.end(nil) }
        await host.close()
        continuation.finish()
    }

    /// Replaces the set of guests the relay will admit into this room, and says whether the room
    /// is open to a guest on no list — which it is exactly while a pairing code is on screen.
    public func updateAllowList(_ keys: [Data], open: Bool = false) async {
        await host.updateAllowList(keys, open: open)
    }

    /// The host's own road stopped, which ends every guest with it.
    ///
    /// Logged with its reason, because from outside this is indistinguishable from a Mac that
    /// simply has no phone: the listener finishes, `RelayRoad` rejoins, and a guest that had
    /// just arrived is left holding a channel to a socket nobody reads.
    private func roadEnded(_ error: Error?) {
        let current = endEverySession(error)
        logger.notice(
            """
            The relay road ended \(error.map { "with \(String(describing: $0))" } ?? "cleanly", privacy: .public), \
            with \(current, privacy: .public) guest sessions on it.
            """)
        continuation.finish()
    }
}
