import Foundation
import ZephraLinkProtocol
import ZephraLinkTransport
import os

/// The relay, as one road that outlives the socket under it.
///
/// `RelayListener` is one join of one room: when the WebSocket goes — the relay's two-hour
/// connection lifetime, a sleeping Mac, a network that moved — its stream of connections
/// finishes and that listener is done. A host told to serve a new listener every time would
/// accumulate one dead listener per reconnection, so the reconnecting lives here instead: one
/// `LinkListener` the host serves once, which yields the guests of each join in turn.
///
/// The wait between attempts is `LinkBackoff`, and the count resets when a guest actually
/// arrives, which is what "a live session" means for the Mac's end.
final class RelayRoad: LinkListener, @unchecked Sendable {
    private let url: URL
    private let identity: DeviceIdentity
    private let logger = Logger(subsystem: "io.zephra", category: "companion")
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation
    private let lock = NSLock()
    private var rejoining: Task<Void, Never>?

    /// A road into this Mac's own room on `url`.
    init(url: URL, identity: DeviceIdentity) {
        self.url = url
        self.identity = identity
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Joins the room, and keeps rejoining it for as long as the road is open.
    func start() {
        let task = Task { [weak self] in
            guard let self else { return }
            await rejoin()
        }
        lock.withLock { rejoining = task }
    }

    func connections() -> AsyncStream<any LinkConnection> { stream }

    func stop() async {
        let task = lock.withLock { () -> Task<Void, Never>? in
            defer { rejoining = nil }
            return rejoining
        }
        task?.cancel()
        await task?.value
        continuation.finish()
    }

    /// One join after another, with a doubling wait between failures.
    private func rejoin() async {
        var attempt = 0
        while !Task.isCancelled {
            let listener = RelayListener(url: url, identity: identity)
            do {
                try await listener.start()
                for await guest in listener.connections() {
                    attempt = 0
                    continuation.yield(guest)
                }
            } catch {
                logger.notice("companion relay could not be joined: \(error.localizedDescription, privacy: .public)")
            }
            await listener.stop()
            guard !Task.isCancelled else { break }
            attempt += 1
            try? await Task.sleep(for: LinkBackoff.delay(after: attempt))
        }
    }
}
