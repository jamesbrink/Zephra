import Foundation
import ZephraLinkProtocol

/// One guest's session on the Mac's relay road.
///
/// The relay gives a host one socket for every phone in its room, so the guest a frame belongs to
/// is written on the frame: the relay stamps `from` on what arrives, and this writes `to` on what
/// leaves. That is what makes a connection per guest honest — each has its own stream, so a phone
/// leaving ends that session and not the road, and `RelayListener` yields a fresh one when the
/// next phone joins.
///
/// A nil `guest` is a relay that names nobody, which is the build before the room held several:
/// its frames go out as they always did, and the room's one phone receives them.
final class RelayGuestSession: LinkConnection, @unchecked Sendable {
    // Lambda invocations can overtake one another by more than the LAN window.
    public var frameReorderingHold: Duration { .seconds(2) }
    private let host: RelayConnection
    /// Which phone this is, as the relay's connection id.
    let guest: String?
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    /// A session writing to one host road, for one guest.
    init(host: RelayConnection, guest: String?) {
        self.host = host
        self.guest = guest
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    func frames() -> AsyncThrowingStream<Data, Error> { stream }

    func send(_ frame: Data) async throws { try await host.send(frame, to: guest) }

    func close() async { continuation.finish() }

    /// One frame the relay forwarded from the guest.
    func deliver(_ frame: Data) { continuation.yield(frame) }

    /// The guest went, or the road did.
    func end(_ error: Error?) {
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }
}
