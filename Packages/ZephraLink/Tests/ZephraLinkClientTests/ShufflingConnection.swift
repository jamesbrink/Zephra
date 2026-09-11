import Foundation
import ZephraLinkProtocol

/// A road that lets frames overtake one another — and, when asked, loses one outright, which is
/// the other thing the relay does.
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
    private let peers: AsyncStream<RelayPeerEvent>
    private let peerSink: AsyncStream<RelayPeerEvent>.Continuation
    private let lock = NSLock()
    private var shuffles = false
    private var swaps = 0
    private var refusesSends = false
    /// How many frames to let past before one is dropped, or nil for a road that drops nothing.
    /// A live run had the relay swallow one small frame with nothing logged at either end; this
    /// is that, made deterministic.
    private var dropCountdown: Int?
    private var dropped = 0

    /// How many frames were let past the one before them, so a test can say it really happened.
    var swapCount: Int { lock.withLock { swaps } }

    /// How many frames this road has thrown away.
    var dropCount: Int { lock.withLock { dropped } }

    /// Loses one frame: the next to arrive, or the one after `skipping` of them.
    func dropFrame(after skipping: Int = 0) { lock.withLock { dropCountdown = skipping } }

    /// Wraps one end of a road.
    init(_ inner: any LinkConnection) {
        self.inner = inner
        (peers, peerSink) = AsyncStream.makeStream()
    }

    /// The relay's word that the other end arrived or went, which only a relay road has.
    func peerEvents() -> AsyncStream<RelayPeerEvent> { peers }

    /// Says the Mac arrived or went, as the relay would.
    func announce(_ event: RelayPeerEvent) { peerSink.yield(event) }

    /// Makes every later `send` fail, which is what a socket the far end has dropped does.
    func refuseSends() { lock.withLock { refusesSends = true } }

    /// Starts letting frames overtake each other.
    func startShuffling() { lock.withLock { shuffles = true } }

    /// Stops, so whatever is in flight lands in the order it was sent.
    func stopShuffling() { lock.withLock { shuffles = false } }

    private var isShuffling: Bool { lock.withLock { shuffles } }

    private func countSwap() { lock.withLock { swaps += 1 } }

    /// Whether this frame is the one to lose, counting down to it as frames go past.
    private func swallows() -> Bool {
        lock.withLock {
            guard let countdown = dropCountdown else { return false }
            guard countdown == 0 else {
                dropCountdown = countdown - 1
                return false
            }
            dropCountdown = nil
            dropped += 1
            return true
        }
    }

    func frames() -> AsyncThrowingStream<Data, Error> {
        let source = inner.frames()
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                var held: Data?
                do {
                    for try await bytes in source {
                        if self?.swallows() == true { continue }
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

    func send(_ frame: Data) async throws {
        guard !lock.withLock({ refusesSends }) else { throw MemoryLinkConnectionError.closed }
        try await inner.send(frame)
    }

    func close() async { await inner.close() }
}
