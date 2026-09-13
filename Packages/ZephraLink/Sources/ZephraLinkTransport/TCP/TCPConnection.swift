import Foundation
import Network
import ZephraLinkProtocol

/// One road over TCP, which is what the phone and the Mac use when they can reach each other.
///
/// TCP is a byte stream and the channel above wants whole frames, so each frame goes out behind
/// a four-byte big-endian length and comes back the same way: read the length, read exactly
/// that many bytes, hand the frame up, begin again. A length past `maxFrameBytes` is not a
/// frame this build will ever send, so it is treated as a broken or hostile peer and the road
/// closes rather than allocating what it asks for.
public final class TCPConnection: LinkConnection, @unchecked Sendable {
    /// The largest frame either end may send. A blob chunk is 64 KiB and a snapshot is a few
    /// hundred kilobytes, so a megabyte is room to spare and a cap an attacker cannot spend.
    public static let maxFrameBytes = 1024 * 1024
    /// How many bytes the length prefix is.
    static let prefixByteCount = 4

    private struct State {
        var isStarted = false
        var isClosed = false
        var readyWaiters: [CheckedContinuation<Void, Error>] = []
        /// Every send whose completion has not fired, so `close` can fail them itself rather
        /// than trust Network to: a send over a path that has gone is never completed.
        var sendWaiters: [UInt64: CheckedContinuation<Void, Error>] = [:]
        var nextSend: UInt64 = 0
    }

    let connection: NWConnection
    let queue = DispatchQueue(label: "io.zephra.link.tcp")
    let frameStream: AsyncThrowingStream<Data, Error>
    let frameContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var state = State()

    /// A road to one address, which connects on the first use or on `start()`.
    public convenience init(host: String, port: UInt16) {
        self.init(
            connection: NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any,
                using: .tcp))
    }

    /// A road over a connection somebody else made: one the listener accepted, or one aimed at
    /// a Bonjour service rather than at an address.
    init(connection: NWConnection) {
        self.connection = connection
        (frameStream, frameContinuation) = AsyncThrowingStream.makeStream()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.readyArrived(nil)
            case .failed(let error): self?.readyArrived(error)
            case .cancelled: self?.readyArrived(TCPConnectionError.closed)
            default: break
            }
        }
    }

    /// Opens the connection and waits for it to be usable.
    ///
    /// Optional: `frames()` and `send(_:)` start it too, since Network queues both until the
    /// connection is ready. It is here for the phone, which wants to know that an address out
    /// of a QR code answers before it starts a handshake against it.
    public func start(timeout: Duration = .seconds(10)) async throws {
        ensureStarted()
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.readyArrived(TCPConnectionError.timedOut)
            await self?.close()
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            let answer: Error?? = lock.withLock {
                if state.isClosed { return .some(TCPConnectionError.closed) }
                if connection.state == .ready { return .some(nil) }
                state.readyWaiters.append(continuation)
                return nil
            }
            switch answer {
            case .some(.some(let error)): continuation.resume(throwing: error)
            case .some(.none): continuation.resume()
            case .none: break
            }
        }
    }

    public func frames() -> AsyncThrowingStream<Data, Error> {
        ensureStarted()
        readNextFrame()
        return frameStream
    }

    public func send(_ frame: Data) async throws {
        guard frame.count <= Self.maxFrameBytes else { throw TCPConnectionError.frameTooLarge }
        ensureStarted()
        var bytes = Data(capacity: Self.prefixByteCount + frame.count)
        withUnsafeBytes(of: UInt32(frame.count).bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(frame)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ticket: UInt64? = lock.withLock {
                guard !state.isClosed else { return nil }
                defer { state.nextSend += 1 }
                state.sendWaiters[state.nextSend] = continuation
                return state.nextSend
            }
            guard let ticket else { return continuation.resume(throwing: TCPConnectionError.closed) }
            connection.send(
                content: bytes,
                completion: .contentProcessed { [weak self] error in
                    guard let waiter = self?.claimSend(ticket) else { return }
                    if let error { waiter.resume(throwing: error) } else { waiter.resume() }
                })
        }
    }

    /// The continuation for one send, if `close` has not already answered it.
    private func claimSend(_ ticket: UInt64) -> CheckedContinuation<Void, Error>? {
        lock.withLock { state.sendWaiters.removeValue(forKey: ticket) }
    }

    public func close() async {
        let waiters: [CheckedContinuation<Void, Error>] = lock.withLock {
            guard !state.isClosed else { return [] }
            state.isClosed = true
            defer {
                state.readyWaiters = []
                state.sendWaiters = [:]
            }
            return state.readyWaiters + state.sendWaiters.values
        }
        for waiter in waiters { waiter.resume(throwing: TCPConnectionError.closed) }
        connection.cancel()
        frameContinuation.finish()
    }

    /// Whether the road has been closed from this end.
    var isClosed: Bool { lock.withLock { state.isClosed } }

    /// Starts the underlying connection once, whichever call gets here first.
    private func ensureStarted() {
        let shouldStart = lock.withLock {
            guard !state.isStarted, !state.isClosed else { return false }
            state.isStarted = true
            return true
        }
        if shouldStart { connection.start(queue: queue) }
    }

    /// Answers everyone waiting on `start()`, with an error or without one.
    private func readyArrived(_ error: Error?) {
        let waiters: [CheckedContinuation<Void, Error>] = lock.withLock {
            defer { state.readyWaiters = [] }
            return state.readyWaiters
        }
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
        if error != nil { frameContinuation.finish(throwing: error) }
    }
}
