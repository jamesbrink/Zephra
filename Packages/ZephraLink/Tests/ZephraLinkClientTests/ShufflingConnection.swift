import Foundation
import ZephraLinkProtocol

/// A road that lets frames overtake one another, which is what the relay does.
///
/// Every `send` through the relay is a Lambda invocation of its own and they post to the far end
/// concurrently, so a frame sealed second can arrive first. This is that, made deterministic
/// enough to test: one frame is held back and released behind the next one, at random, for as
/// long as `startShuffling` says.
///
/// Only the reading half reorders. The handshake's plaintext messages are read before shuffling
/// starts, since a `confirm` that overtook a `hello` is not a thing any relay could do — the
/// phone sends them one after the other on one connection.
final class ShufflingConnection: LinkConnection, @unchecked Sendable {
    private let inner: any LinkConnection
    private let lock = NSLock()
    private var shuffles = false
    private var swaps = 0

    /// How many frames were let past the one before them, so a test can say it really happened.
    var swapCount: Int { lock.withLock { swaps } }

    /// Wraps one end of a road.
    init(_ inner: any LinkConnection) {
        self.inner = inner
    }

    /// Starts letting frames overtake each other.
    func startShuffling() { lock.withLock { shuffles = true } }

    /// Stops, so whatever is in flight lands in the order it was sent.
    func stopShuffling() { lock.withLock { shuffles = false } }

    private var isShuffling: Bool { lock.withLock { shuffles } }

    private func countSwap() { lock.withLock { swaps += 1 } }

    func frames() -> AsyncThrowingStream<Data, Error> {
        let source = inner.frames()
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                var held: Data?
                do {
                    for try await bytes in source {
                        if let waiting = held {
                            held = nil
                            self?.countSwap()
                            continuation.yield(bytes)
                            continuation.yield(waiting)
                        } else if self?.isShuffling == true, Bool.random() {
                            held = bytes
                        } else {
                            continuation.yield(bytes)
                        }
                    }
                    if let held { continuation.yield(held) }
                    continuation.finish()
                } catch {
                    if let held { continuation.yield(held) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ frame: Data) async throws { try await inner.send(frame) }

    func close() async { await inner.close() }
}
