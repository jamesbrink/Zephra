import Foundation
import ZephraLinkProtocol
import os

/// One road through the relay, for when neither end can reach the other directly.
///
/// A `URLSessionWebSocketTask` rather than Network's own WebSocket: it is the one that works
/// the same on both platforms without a server that sets headers for it, and API Gateway's
/// WebSocket API carries text frames, which is what this sends.
///
/// The relay copies bytes and never sees inside them — a `send` payload is one sealed frame —
/// so this type is a road and not a trust boundary. It does not reconnect: the owner does, with
/// a fresh handshake, because a reconnection is a new session and pretending otherwise would
/// hand the channel above a stream with a hole in it.
public final class RelayConnection: LinkConnection, @unchecked Sendable {
    /// How long the relay has to answer a join before the road gives up on it.
    ///
    /// A join that hangs is worse than one that fails: the backoff loop that retries the road
    /// sits *after* this call, so a socket the relay accepts and then ignores stops the Mac
    /// rejoining its room at all, for the life of the process and in silence.
    public static let joinDeadline: Duration = .seconds(15)

    /// How often to ping, against the relay's ten-minute idle timeout.
    public static let pingInterval: Duration = .seconds(300)

    struct State {
        var isClosed = false
        var isJoined = false
        /// The guests this host will admit, as raw signing keys. Empty for a guest, which sends
        /// no list at all.
        var allow: [Data] = []
        /// Whether this host's room admits a guest that is on no list, which is true only while
        /// a pairing code is on screen.
        var isOpen = false
        var reader: Task<Void, Never>?
        var pinger: Task<Void, Never>?
    }

    let task: URLSessionWebSocketTask
    let handshake: RelayHandshake
    /// Which end of the room this is, which is what decides whether it carries an allow-list.
    public let role: RelayRole
    let logger = Logger(subsystem: "io.zephra", category: "link.relay")
    let frameStream: AsyncThrowingStream<Data, Error>
    let frameContinuation: AsyncThrowingStream<Data, Error>.Continuation
    let peerContinuation: AsyncStream<RelayPeerEvent>.Continuation
    let peerStream: AsyncStream<RelayPeerEvent>
    /// The slices of payloads too big for one WebSocket frame, put back together here.
    let fragments = RelayFragments()
    /// Not private: `RelayConnection+Closing` is the rest of this type, and the lock is what
    /// the two halves share.
    let lock = NSLock()
    var state = State()

    /// A road into one room, as one role. Nothing happens until `start()`.
    public init(
        url: URL, identity: DeviceIdentity, room: RoomID, role: RelayRole,
        session: URLSession = .shared
    ) {
        task = session.webSocketTask(with: url)
        self.role = role
        handshake = RelayHandshake(identity: identity, room: room, role: role)
        (frameStream, frameContinuation) = AsyncThrowingStream.makeStream()
        (peerStream, peerContinuation) = AsyncStream.makeStream()
    }

    /// Opens the socket and joins the room, or throws the relay's refusal.
    ///
    /// Every message up to `joined` is read here rather than by the pump, so a refusal is an
    /// error the caller can show rather than a stream that ends for no stated reason. Nothing
    /// is sent until the relay says `joined`: its connection index is eventually consistent.
    public func start() async throws {
        task.resume()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.join() }
                group.addTask {
                    try await Task.sleep(for: Self.joinDeadline)
                    throw RelayError.timedOut
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            await close()
            throw error
        }
    }

    /// Everything up to `joined`, with no clock of its own; `start()` holds the clock.
    private func join() async throws {
        try await write(handshake.opening)
        while true {
            let message = try await read()
            let room = lock.withLock { (allow: state.allow, isOpen: state.isOpen) }
            switch try handshake.receive(message, allow: room.allow, open: room.isOpen) {
            case .send(let answer): try await write(answer)
            case .ignore: continue
            case .joined:
                lock.withLock { state.isJoined = true }
                startPumps()
                return
            }
        }
    }

    public func frames() -> AsyncThrowingStream<Data, Error> { frameStream }

    /// The other end arriving and going, which is how a Mac knows a phone is there and how a
    /// phone knows the Mac is asleep without waiting for a request to time out.
    public func peerEvents() -> AsyncStream<RelayPeerEvent> { peerStream }

    /// Replaces the set of guests the relay will admit into this room, and says whether the room
    /// is open to a guest on no list at all.
    ///
    /// Kept here rather than handed in at `init` because both move while the socket is up: a
    /// pairing completes, a device is revoked, a code goes up or comes down. Called before
    /// `start()` it is what the join carries; called after, it goes as its own message. A guest
    /// sends none of this, and the relay ignores either from anything but the host that owns the
    /// room.
    public func updateAllowList(_ keys: [Data], open: Bool = false) async {
        let trimmed = Array(keys.prefix(RelayJoin.allowLimit))
        let isLive = lock.withLock { () -> Bool in
            state.allow = trimmed
            state.isOpen = open
            return state.isJoined && !state.isClosed
        }
        guard isLive, role == .host else { return }
        try? await write(.allow(pubs: trimmed, open: open ? true : nil))
    }

    /// One sealed frame to the other end, cut into slices where it is too big for one frame.
    ///
    /// API Gateway allows a 128 KB *message* but a 32 KB *frame*, and `URLSessionWebSocketTask`
    /// sends a message as one frame: a 64 KiB blob chunk sealed and base64'd is about 87 KB, and
    /// the relay closed the socket on the first one with nothing said about why. So a large
    /// payload goes as `RelayFragment` slices, which the far end puts back together.
    ///
    /// A write that fails takes the road down with it. The socket is dead either way, and a road
    /// that stays open over a dead socket is a session the Mac keeps and the phone cannot reach:
    /// the failure finishes `frames()`, which is what everything above reads the end of a
    /// session from.
    public func send(_ frame: Data) async throws {
        guard lock.withLock({ state.isJoined && !state.isClosed }) else { throw RelayError.closed }
        do {
            for message in RelayFragment.messages(for: frame) { try await write(message) }
        } catch {
            logger.notice(
                "The relay socket refused a frame: \(error.localizedDescription, privacy: .public)")
            fail(error)
            throw error
        }
    }
}
