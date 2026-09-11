import Foundation
import ZephraLinkProtocol

/// One phone, from the moment it connects until the road closes.
///
/// It owns a handshake, a channel and two tasks: a reader draining the connection's frames and a
/// writer draining everything this Mac has to say. The writer exists so a phone on a slow link
/// can never hold the main actor — a `send` is a yield into a stream and returns at once, and
/// the bytes leave on a task of their own, in the order they were sealed.
///
/// The session writes nothing to the Mac's own interface. Commands go through
/// `GenerationStore.enqueue` and the library index's own mutations, which is what keeps a
/// request from a phone from touching the capsule, the canvas or the query.
@MainActor
public final class CompanionSession: Identifiable {
    /// This session's identity, for logging and for a list.
    public let id = UUID()
    /// Who is on the other end, once the handshake has proved it.
    public internal(set) var peer: DevicePublicKeys?
    /// What the phone calls itself, as it said in its `Hello`.
    public internal(set) var deviceName = ""
    /// Whether the channel is open and the snapshot has gone.
    public internal(set) var isReady = false

    let connection: any LinkConnection
    weak var host: CompanionHost?
    /// The handshake in progress, from the `hello` until the `confirm` settles it. Nil after
    /// that: `channel` is what says the session is past the plaintext stage.
    var responder: HandshakeResponder?
    /// Whether the `Hello` asked to pair, which is what makes a wrong `confirm` a guess at the
    /// code on screen rather than a stale device reconnecting.
    var isPairingAttempt = false
    var channel: SecureChannel?
    var isClosed = false
    /// The blob arriving from the phone right now — a reference picture — and the ones that have
    /// landed, kept until an `enqueue` names one.
    var incoming: BlobReassembly?
    var incomingID: UUID?
    var blobs: [UUID: Data] = [:]
    /// The order they landed in, so the one dropped when the limit is reached is the oldest and
    /// not whichever the dictionary happened to hand back first.
    var blobOrder: [UUID] = []

    private let outbound: AsyncStream<Data>
    private let sink: AsyncStream<Data>.Continuation
    private var writer: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    /// The clock on the plaintext stage, cancelled the moment there is a channel.
    private var deadline: Task<Void, Never>?

    /// How many finished blobs a session holds before the oldest is dropped. A phone sends one
    /// reference picture and then asks for a generation; more than a couple waiting means a
    /// phone that sends and never asks, and that is not memory this Mac should keep.
    static let blobLimit = 4

    /// Prepares a session. Nothing is read until `start()`.
    init(connection: any LinkConnection, host: CompanionHost) {
        self.connection = connection
        self.host = host
        (outbound, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Whether the handshake is behind it: `channel` is what says the plaintext stage is over.
    var isAuthenticated: Bool { channel != nil }

    /// Starts the two tasks — bytes out, frames in — and the clock on the handshake.
    func start() {
        writer = Self.writerTask(connection: connection, outbound: outbound, session: self)
        reader = Task { @MainActor [weak self] in await self?.run() }
        let wait = host?.handshakeDeadline ?? .seconds(10)
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, !isAuthenticated else { return }
            host?.logger.notice("companion closed a connection that never finished its handshake")
            await close()
        }
    }

    /// The handshake is behind it, so the clock stops.
    func handshakeSettled() {
        deadline?.cancel()
        deadline = nil
    }

    /// Closes the session, optionally telling the phone why first.
    ///
    /// The error goes out before the stream is finished, so a revocation reaches the phone
    /// rather than being dropped with everything else still queued.
    public func close(telling error: LinkError? = nil) async {
        guard !isClosed else { return }
        // Before the flag, not after: `enqueue` refuses a closed session, and a refusal the
        // phone never receives is a phone left guessing why the connection went.
        if let error { try? sendError(error) }
        isClosed = true
        isReady = false
        handshakeSettled()
        sink.finish()
        await writer?.value
        writer = nil
        await connection.close()
        channel?.close()
        reader?.cancel()
        host?.forget(self)
    }

    /// Hands one already-framed message to the writer.
    func enqueue(_ bytes: Data) {
        guard !isClosed else { return }
        sink.yield(bytes)
    }

    /// Whether this session speaks for `keys`, which is what a revocation asks.
    func belongs(to keys: DevicePublicKeys) -> Bool { peer == keys }

    /// The writer: one task per session, draining the stream and never touching the main actor
    /// until it has nothing left to send.
    private static func writerTask(
        connection: any LinkConnection, outbound: AsyncStream<Data>, session: CompanionSession
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            for await bytes in outbound {
                do {
                    try await connection.send(bytes)
                } catch {
                    break
                }
            }
            await session.writerStopped()
        }
    }

    /// The writer has finished, either because the session is closing or because the road broke.
    /// The task is dropped first, so the `close` below does not wait on itself.
    private func writerStopped() async {
        writer = nil
        await close()
    }
}

extension CompanionSession: Equatable {
    public nonisolated static func == (lhs: CompanionSession, rhs: CompanionSession) -> Bool {
        lhs === rhs
    }
}
