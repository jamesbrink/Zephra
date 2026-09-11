import Foundation
import Network
import ZephraLinkProtocol

/// The Mac's side of a TCP road: a port phones connect to, and the Bonjour name that finds it.
///
/// The advertiser is not a type of its own. `NWListener` publishes the service itself, and a
/// separate `BonjourAdvertiser` would have to be handed the port the listener chose and kept in
/// step with its lifetime — two objects that can only ever be right together. So advertising is
/// an argument: `TCPListener(advertising: room)` publishes `_zephra._tcp` with the room in its
/// TXT record as soon as the port is known, and stops when the listener does.
public final class TCPListener: LinkListener, @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.zephra.link.listener")
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation
    private let lock = NSLock()
    private var readyWaiters: [CheckedContinuation<UInt16, Error>] = []

    /// A listener on `port`, or on one the system picks when that is nil.
    ///
    /// `advertising` is the room a phone matches a discovered Mac against; nil keeps the
    /// listener off Bonjour altogether, which is what a Mac that has never shown a pairing code
    /// wants.
    public init(port: UInt16? = nil, advertising room: RoomID? = nil, name: String = "Zephra") throws {
        let endpointPort = port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        listener = try NWListener(using: .tcp, on: endpointPort)
        if let room {
            listener.service = NWListener.Service(
                name: name, type: BonjourService.type, domain: nil,
                txtRecord: BonjourService.txtRecord(room: room))
        }
        (stream, continuation) = AsyncStream.makeStream()
        listener.newConnectionHandler = { [weak self] connection in
            self?.continuation.yield(TCPConnection(connection: connection))
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.settle(.success(self?.port ?? 0))
            case .failed(let error): self?.settle(.failure(error))
            case .cancelled: self?.settle(.failure(TCPConnectionError.notListening))
            default: break
            }
        }
    }

    /// The port it is listening on, once it is listening.
    public var port: UInt16? { listener.port?.rawValue }

    /// Starts listening and answers the port it took.
    public func start(timeout: Duration = .seconds(10)) async throws -> UInt16 {
        listener.start(queue: queue)
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.settle(.failure(TCPConnectionError.timedOut))
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            if let port, listener.state == .ready {
                continuation.resume(returning: port)
            } else {
                lock.withLock { readyWaiters.append(continuation) }
            }
        }
    }

    public func connections() -> AsyncStream<any LinkConnection> { stream }

    public func stop() async {
        settle(.failure(TCPConnectionError.notListening))
        listener.cancel()
        continuation.finish()
    }

    /// Answers everyone waiting on `start()`, once.
    private func settle(_ result: Result<UInt16, Error>) {
        let waiters: [CheckedContinuation<UInt16, Error>] = lock.withLock {
            defer { readyWaiters = [] }
            return readyWaiters
        }
        for waiter in waiters { waiter.resume(with: result) }
    }
}
