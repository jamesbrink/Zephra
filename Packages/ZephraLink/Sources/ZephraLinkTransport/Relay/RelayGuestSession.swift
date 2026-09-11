import Foundation
import ZephraLinkProtocol

/// One guest's turn on the Mac's relay road.
///
/// The relay multiplexes nothing: a host has one socket and a frame arriving on it carries no
/// guest id, so the Mac cannot tell two phones apart over the relay. This is the shape that
/// makes that honest — a connection per guest that all write to the one socket, with only one
/// alive at a time. Its stream is its own, so a guest leaving ends that session and not the
/// road; `RelayListener` finishes it and yields a fresh one when the next guest joins.
final class RelayGuestSession: LinkConnection, @unchecked Sendable {
    private let host: RelayConnection
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    /// A session writing to one host road.
    init(host: RelayConnection) {
        self.host = host
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    func frames() -> AsyncThrowingStream<Data, Error> { stream }

    func send(_ frame: Data) async throws { try await host.send(frame) }

    func close() async { continuation.finish() }

    /// One frame the relay forwarded from the guest.
    func deliver(_ frame: Data) { continuation.yield(frame) }

    /// The guest went, or the road did.
    func end(_ error: Error?) {
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }
}
