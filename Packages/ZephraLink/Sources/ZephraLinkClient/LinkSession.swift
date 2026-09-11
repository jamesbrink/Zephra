import Foundation
import ZephraLinkProtocol

/// One connection to one Mac, from the road under it to the channel over it.
///
/// A class rather than three properties on the client, so the reader task can ask "am I still
/// the session?" by identity: a road that fails while another is already being opened must not
/// tear the new one down. `channel` is nil until the handshake finishes, which is also what
/// says a frame arriving now is one of the three plaintext ones.
@MainActor
final class LinkSession {
    /// The road underneath.
    let road: any LinkConnection
    /// Which road it is, for the state the interface shows.
    let kind: LinkRoad
    /// The sealed channel, once the handshake has made one.
    var channel: SecureChannel?
    /// The task reading `road.frames()`.
    var reader: Task<Void, Never>?
    /// The plaintext frames that arrived before anyone asked for them.
    var handshakeInbox: [Data] = []
    /// Whoever is waiting for the next plaintext frame.
    var handshakeWaiter: CheckedContinuation<Data, any Error>?

    /// Opens a session over one road.
    init(road: any LinkConnection, kind: LinkRoad) {
        self.road = road
        self.kind = kind
    }

    /// Hands one plaintext frame to whoever is waiting, or keeps it until someone is.
    func deliverPlaintext(_ bytes: Data) {
        if let waiter = handshakeWaiter {
            handshakeWaiter = nil
            waiter.resume(returning: bytes)
        } else {
            handshakeInbox.append(bytes)
        }
    }

    /// The next plaintext frame, which is how the handshake reads its two answers.
    func nextPlaintext() async throws -> Data {
        if !handshakeInbox.isEmpty { return handshakeInbox.removeFirst() }
        return try await withCheckedThrowingContinuation { handshakeWaiter = $0 }
    }

    /// Stops everything this session holds.
    func end(_ error: any Error) async {
        reader?.cancel()
        reader = nil
        channel?.close()
        if let waiter = handshakeWaiter {
            handshakeWaiter = nil
            waiter.resume(throwing: error)
        }
        await road.close()
    }
}
