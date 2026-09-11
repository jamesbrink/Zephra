import Foundation
import ZephraLinkProtocol

/// One connection to one Mac, from the road under it to the channel over it.
///
/// A class rather than three properties on the client, so the reader task can ask "am I still
/// the session?" by identity: a road that fails while another is already being opened must not
/// tear the new one down. `channel` is nil until the handshake finishes, which is also what
/// says a frame arriving now is one of the three plaintext ones.
///
/// Everything sealed goes out through one `AsyncStream<Data>` drained by a writer task of its
/// own, which is the Mac's shape for the Mac's reason: the channel's nonce is a frame's position
/// in the stream, so the order frames are sealed in must be the order they leave in. Sealing and
/// yielding are one step on the main actor, with no await between them, so two requests and an
/// answered ping cannot interleave and leave the far end unable to open what arrives.
@MainActor
final class LinkSession {
    /// The road underneath.
    let road: any LinkConnection
    /// Which road it is, for the state the interface shows.
    let kind: LinkRoad
    /// The sealed channel, once the handshake has made one.
    var channel: SecureChannel?
    /// Everything the Mac says, released in the order it was sealed in. The relay is several
    /// concurrent invocations, so the road is not ordered and this is what makes it so again.
    var inbox: OrderedInbox?
    /// The task reading `road.frames()`.
    var reader: Task<Void, Never>?
    /// The plaintext frames that arrived before anyone asked for them.
    var handshakeInbox: [Data] = []
    /// Whoever is waiting for the next plaintext frame.
    var handshakeWaiter: CheckedContinuation<Data, any Error>?

    private let outbound: AsyncStream<Data>
    private let sink: AsyncStream<Data>.Continuation
    private var writer: Task<Void, Never>?

    /// Opens a session over one road, with its writer already draining.
    init(road: any LinkConnection, kind: LinkRoad) {
        self.road = road
        self.kind = kind
        (outbound, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        writer = Self.writerTask(road: road, outbound: outbound)
    }

    /// Seals one frame and hands it to the writer, in one step.
    ///
    /// Synchronous on purpose: an await between taking the counter and queueing the bytes is
    /// exactly where a second caller could take the next counter and reach the socket first.
    func send(_ frame: Frame) throws {
        guard let channel else { throw LinkClientError.notConnected }
        sink.yield(try channel.seal(frame))
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
        sink.finish()
        await writer?.value
        writer = nil
        inbox?.stop()
        channel?.close()
        if let waiter = handshakeWaiter {
            handshakeWaiter = nil
            waiter.resume(throwing: error)
        }
        await road.close()
    }

    /// The writer: one task per session, draining the stream in the order it was sealed in.
    ///
    /// A send that fails closes the road rather than reporting: the reader is the one place a
    /// session is torn down, and a closed road is what it notices.
    private static func writerTask(
        road: any LinkConnection, outbound: AsyncStream<Data>
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            for await bytes in outbound {
                do { try await road.send(bytes) } catch { return await road.close() }
            }
        }
    }
}
