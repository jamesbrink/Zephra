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
    /// How often to ping, against the relay's ten-minute idle timeout.
    public static let pingInterval: Duration = .seconds(300)

    struct State {
        var isClosed = false
        var isJoined = false
        var reader: Task<Void, Never>?
        var pinger: Task<Void, Never>?
    }

    let task: URLSessionWebSocketTask
    let handshake: RelayHandshake
    let logger = Logger(subsystem: "io.zephra", category: "link.relay")
    let frameStream: AsyncThrowingStream<Data, Error>
    let frameContinuation: AsyncThrowingStream<Data, Error>.Continuation
    let peerContinuation: AsyncStream<RelayPeerEvent>.Continuation
    /// The other end arriving and going, which is how a Mac knows a phone is there and how a
    /// phone knows the Mac is asleep without waiting for a request to time out.
    public let peerEvents: AsyncStream<RelayPeerEvent>
    private let lock = NSLock()
    private var state = State()

    /// A road into one room, as one role. Nothing happens until `start()`.
    public init(
        url: URL, identity: DeviceIdentity, room: RoomID, role: RelayRole,
        session: URLSession = .shared
    ) {
        task = session.webSocketTask(with: url)
        handshake = RelayHandshake(identity: identity, room: room, role: role)
        (frameStream, frameContinuation) = AsyncThrowingStream.makeStream()
        (peerEvents, peerContinuation) = AsyncStream.makeStream()
    }

    /// Opens the socket and joins the room, or throws the relay's refusal.
    ///
    /// Every message up to `joined` is read here rather than by the pump, so a refusal is an
    /// error the caller can show rather than a stream that ends for no stated reason. Nothing
    /// is sent until the relay says `joined`: its connection index is eventually consistent.
    public func start() async throws {
        task.resume()
        try await write(handshake.opening)
        while true {
            let message = try await read()
            switch try handshake.receive(message) {
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

    public func send(_ frame: Data) async throws {
        guard lock.withLock({ state.isJoined && !state.isClosed }) else { throw RelayError.closed }
        try await write(.send(payload: frame))
    }

    public func close() async {
        let running: State? = lock.withLock {
            guard !state.isClosed else { return nil }
            state.isClosed = true
            return state
        }
        guard let running else { return }
        running.reader?.cancel()
        running.pinger?.cancel()
        task.cancel(with: .goingAway, reason: nil)
        frameContinuation.finish()
        peerContinuation.finish()
    }

    /// Whether this road has been closed from this end.
    var isClosed: Bool { lock.withLock { state.isClosed } }

    /// Keeps the two long-lived tasks, so `close()` can stop them.
    func hold(reader: Task<Void, Never>, pinger: Task<Void, Never>) {
        let alreadyClosed = lock.withLock { () -> Bool in
            guard !state.isClosed else { return true }
            state.reader = reader
            state.pinger = pinger
            return false
        }
        if alreadyClosed {
            reader.cancel()
            pinger.cancel()
        }
    }
}
