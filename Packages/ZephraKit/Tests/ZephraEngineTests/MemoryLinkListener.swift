import Foundation
import ZephraLinkProtocol

/// A listener a test hands connections to by hand.
///
/// The real ones are a TCP socket and a relay's WebSocket; what the host asks of either is this
/// much — a stream of connections and a way to stop.
final class MemoryLinkListener: LinkListener, @unchecked Sendable {
    private let stream: AsyncStream<any LinkConnection>
    private let continuation: AsyncStream<any LinkConnection>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func connections() -> AsyncStream<any LinkConnection> { stream }

    /// Hands the host one end of a road a test has just made.
    func offer(_ connection: any LinkConnection) { continuation.yield(connection) }

    func stop() async { continuation.finish() }
}
