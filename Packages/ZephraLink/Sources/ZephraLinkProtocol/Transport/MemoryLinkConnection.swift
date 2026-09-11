import Foundation

/// Two ends of a road that never leaves the process, for tests and for a frozen preview.
///
/// `pair()` hands back both ends; what one sends the other reads. Closing either end
/// finishes both streams, as a real road would.
public final class MemoryLinkConnection: LinkConnection, @unchecked Sendable {
    private let inbound: AsyncThrowingStream<Data, Error>
    private let inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var peer: MemoryLinkConnection?
    private var isClosed = false

    private init() {
        (inbound, inboundContinuation) = AsyncThrowingStream.makeStream()
    }

    /// Both ends of one road.
    public static func pair() -> (MemoryLinkConnection, MemoryLinkConnection) {
        let a = MemoryLinkConnection()
        let b = MemoryLinkConnection()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    public func frames() -> AsyncThrowingStream<Data, Error> { inbound }

    public func send(_ frame: Data) async throws {
        let target: MemoryLinkConnection? = lock.withLock { isClosed ? nil : peer }
        guard let target else { throw MemoryLinkConnectionError.closed }
        target.inboundContinuation.yield(frame)
    }

    public func close() async {
        let other: MemoryLinkConnection? = lock.withLock {
            guard !isClosed else { return nil }
            isClosed = true
            return peer
        }
        inboundContinuation.finish()
        if let other { await other.close() }
    }
}

/// The one way an in-memory road fails: a send after either end closed.
public enum MemoryLinkConnectionError: Error, Sendable {
    case closed
}
