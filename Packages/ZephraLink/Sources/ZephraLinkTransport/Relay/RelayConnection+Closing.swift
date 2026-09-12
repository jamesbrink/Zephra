import Foundation
import ZephraLinkProtocol

/// Every way this road stops, and the tasks it has to stop with it.
///
/// Apart from the file above because the rule is one rule and it is worth stating once: a road
/// that cannot carry finishes `frames()`. That is what every session over a relay reads the end
/// of its road from, and a road that stayed open over a dead socket was a Mac holding a channel
/// no phone could reach.
extension RelayConnection {
    /// The socket is gone, from a read that failed or a write that did. Marks the road closed and
    /// finishes both streams, so the session over it ends rather than waiting on a dead socket.
    func fail(_ error: any Error) {
        let wasOpen: Bool = lock.withLock {
            guard !state.isClosed else { return false }
            state.isClosed = true
            return true
        }
        guard wasOpen else { return }
        let running = lock.withLock { state }
        running.reader?.cancel()
        running.pinger?.cancel()
        task.cancel(with: .goingAway, reason: nil)
        frameContinuation.finish(throwing: error)
        signalContinuation.finish(throwing: error)
        peerContinuation.finish()
        errorContinuation.finish()
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
        signalContinuation.finish()
        peerContinuation.finish()
        errorContinuation.finish()
    }

    /// Whether this road has been closed from this end.
    var isClosed: Bool { lock.withLock { state.isClosed } }

    /// Marks the road closed as its reader stops, and says whether it was already closed —
    /// which is what tells a close from this end apart from a socket that went on its own.
    func readerStopped() -> Bool {
        lock.withLock {
            defer { state.isClosed = true }
            return state.isClosed
        }
    }

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
