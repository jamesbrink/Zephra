import Foundation
import ZephraLinkProtocol

/// Reading the room once it is joined, and keeping the socket alive while nothing is said.
extension RelayConnection {
    /// One relay message read off the socket.
    func read() async throws -> RelayMessage {
        let bytes: Data
        switch try await task.receive() {
        case .string(let text): bytes = Data(text.utf8)
        case .data(let data): bytes = data
        @unknown default: throw RelayError.malformed
        }
        guard let message = try? LinkJSON.decode(RelayMessage.self, from: bytes) else {
            throw RelayError.malformed
        }
        return message
    }

    /// One relay message written to it, as text: API Gateway's WebSocket API carries no others.
    func write(_ message: RelayMessage) async throws {
        let bytes = try LinkJSON.encode(message)
        try await task.send(.string(String(decoding: bytes, as: UTF8.self)))
    }

    /// Starts the two tasks a joined room runs: one reading it, one keeping it open.
    func startPumps() {
        let reader = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { self.dispatch(try await self.read()) } catch {
                    self.streamEnded(error)
                    return
                }
            }
        }
        let pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RelayConnection.pingInterval)
                guard let self, !Task.isCancelled else { return }
                try? await self.write(.ping)
            }
        }
        hold(reader: reader, pinger: pinger)
    }

    /// What one message off a joined room means.
    ///
    /// An `error` on a joined connection leaves it open, per the relay's own rules, so it is
    /// logged and the road carries on: the frame that caused it is the caller's problem, and a
    /// frame that never arrives is a gap the far end's `OrderedInbox` waits out and then calls
    /// loss.
    private func dispatch(_ message: RelayMessage) {
        switch message {
        case .send:
            // A payload that came in slices is yielded once, whole. Slices arrive out of order,
            // because every `send` is a Lambda invocation of its own, so `RelayFragments` holds
            // them by message id until the set is complete.
            if let whole = fragments.accept(message) { frameContinuation.yield(whole) }
        case .peer(let event): peerContinuation.yield(event)
        case .error(let reason): logger.error("The relay refused a frame: \(reason, privacy: .public)")
        case .allowed(let count):
            logger.debug("The relay now holds \(count, privacy: .public) allowed keys.")
        case .hello, .challenge, .join, .joined, .allow, .ping, .pong: break
        }
    }

    /// The socket stopped. A close from this end finishes the stream; anything else fails it.
    ///
    /// Either way the road is marked closed before the stream finishes, so a `send` that arrives
    /// after this is refused here rather than written into a socket that is gone.
    private func streamEnded(_ error: Error) {
        if readerStopped() {
            frameContinuation.finish()
        } else {
            frameContinuation.finish(throwing: error)
        }
        peerContinuation.finish()
    }
}
