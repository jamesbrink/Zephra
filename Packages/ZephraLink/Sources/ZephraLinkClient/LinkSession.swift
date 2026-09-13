import Foundation
import ZephraLinkProtocol
import os

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
    let id = UUID()
    let road: any LinkConnection
    /// Which road it is, for the state the interface shows.
    let kind: LinkRoad
    /// The sealed channel, once the handshake has made one.
    var channel: SecureChannel?
    /// Cached state cannot negotiate features on a new authenticated session.
    var hasSnapshot = false
    var uploadTimings = InputTransferTimings()
    /// Everything the Mac says, released in the order it was sealed in. The relay is several
    /// concurrent invocations, so the road is not ordered and this is what makes it so again.
    var inbox: OrderedInbox?
    /// The task reading `road.frames()`.
    var reader: Task<Void, Never>?
    /// The task watching the road for the Mac leaving, where the road can tell. The relay can,
    /// and a `left` is the Mac asleep or its own socket gone: it ends this session at once
    /// rather than leaving every request to time out against a room with nobody in it.
    var peers: Task<Void, Never>?
    /// The task watching the road's own refusals — the relay's `error` frames — which are frames
    /// this end sealed that the Mac will never see. Logged, never fatal: what the missing frame
    /// costs is a gap at the far end, and a gap is now something both ends recover from.
    var roadErrors: Task<Void, Never>?
    /// The plaintext frames that arrived before anyone asked for them.
    var handshakeInbox: [Data] = []
    /// Whoever is waiting for the next plaintext frame.
    var handshakeWaiter: CheckedContinuation<Data, any Error>?

    private let outbound: AsyncStream<Data>
    private let sink: AsyncStream<Data>.Continuation
    private var writer: Task<Void, Never>?
    var queuedBytes = 0
    var ended = false

    /// Opens a session over one road, with its writer already draining.
    init(road: any LinkConnection, kind: LinkRoad) {
        self.road = road
        self.kind = kind
        (outbound, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        writer = Self.writerTask(road: road, outbound: outbound, session: self)
    }

    /// Seals one frame and hands it to the writer, in one step.
    ///
    /// Synchronous on purpose: an await between taking the counter and queueing the bytes is
    /// exactly where a second caller could take the next counter and reach the socket first.
    func send(_ frame: Frame) throws {
        guard let channel else { throw LinkClientError.notConnected }
        guard !ended, queuedBytes < 8_388_608 else { throw LinkClientError.notConnected }
        let bytes = try channel.seal(frame)
        queuedBytes += bytes.count
        sink.yield(bytes)
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
        ended = true
        reader?.cancel()
        reader = nil
        peers?.cancel()
        peers = nil
        roadErrors?.cancel()
        roadErrors = nil
        sink.finish()
        inbox?.stop()
        channel?.close()
        if let waiter = handshakeWaiter {
            handshakeWaiter = nil
            waiter.resume(throwing: error)
        }
        // The road is closed **before** the writer is waited on. A writer in the middle of a send
        // over a road whose interface has gone never returns on its own: Network hands the bytes
        // to nothing and the completion never fires, so a session ended the other way round sat
        // on that await for good — the phone never dialled again and read as reconnecting for
        // as long as the app was open. Closing the road is what fails that send, and nothing
        // still queued at the end of a session is owed delivery.
        await road.close()
        await writer?.value
        writer = nil
    }

    /// The writer: one task per session, draining the stream in the order it was sealed in.
    ///
    /// A send that fails closes the road rather than reporting: the reader is the one place a
    /// session is torn down, and a closed road is what it notices. It is logged at error first,
    /// with what was in flight and what went wrong — a frame that left this phone and reached
    /// nobody is otherwise the quietest failure in the link.
    private static func writerTask(
        road: any LinkConnection, outbound: AsyncStream<Data>, session: LinkSession
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            for await bytes in outbound {
                do {
                    try await road.send(bytes)
                    await session.sent(bytes.count)
                } catch {
                    Self.logger.error(
                        """
                        A frame of \(bytes.count, privacy: .public) bytes did not leave this                         phone: \(String(describing: error), privacy: .public)
                        """)
                    return await road.close()
                }
            }
        }
    }

    private func sent(_ count: Int) { queuedBytes -= count }

    func capacity() async throws {
        while queuedBytes >= 262_144 && !ended { try await Task.sleep(for: .milliseconds(5)) }
        guard !ended else { throw LinkClientError.notConnected }
        try Task.checkCancellation()
    }

    /// The log this session's writer uses, which runs off the main actor.
    private nonisolated static let logger = Logger(subsystem: "io.zephra", category: "link.client")
}
