import Foundation
import ZephraLinkProtocol

/// A road whose sends hang until it is closed, which is what a socket to a phone that has gone
/// does: the buffers fill, the completion waits on acknowledgements that never come, and
/// nothing but closing the road fails the send.
final class StallingConnection: LinkConnection, @unchecked Sendable {
    private let inner: any LinkConnection
    private let lock = NSLock()
    private var stalls = false
    private var stalled: [CheckedContinuation<Void, any Error>] = []

    /// Wraps one end of a road.
    init(_ inner: any LinkConnection) { self.inner = inner }

    /// Makes every later `send` hang until `close()`.
    func stallSends() { lock.withLock { stalls = true } }

    func frames() -> AsyncThrowingStream<Data, Error> { inner.frames() }

    func send(_ frame: Data) async throws {
        if lock.withLock({ stalls }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock { stalled.append(continuation) }
            }
        }
        try await inner.send(frame)
    }

    func close() async {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { stalled = [] }
            return stalled
        }
        for waiter in waiting { waiter.resume(throwing: MemoryLinkConnectionError.closed) }
        await inner.close()
    }
}
