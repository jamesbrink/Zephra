import Foundation
import ZephraLinkProtocol

/// A Mac at the other end of a road that never leaves the process.
///
/// It runs the real `HandshakeResponder` and the real `SecureChannel`, so what the client's
/// suite exercises is the whole session and not a mock of one: the same three plaintext
/// messages, the same sealed frames, the same envelopes.
@MainActor
final class FakeHost {
    /// The Mac's identity, whose keys a pairing payload publishes.
    let identity: DeviceIdentity
    /// The commands the phone sent, in order.
    private(set) var commands: [Command] = []
    /// The blobs the phone sent, whole.
    private(set) var blobs: [Data] = []
    /// What a `fetchThumbnail` or `fetchFile` answers with, or nil to refuse.
    var payload: Data?
    /// What the phone's next command is answered with, where `.ok` will not do.
    var reply: Reply?

    private var secret: Data?
    private var known: Set<Data>
    private var road: (any LinkConnection)?
    private var responder: HandshakeResponder?
    private var channel: SecureChannel?
    private var assembling: [UUID: BlobReassembly] = [:]
    private var task: Task<Void, Never>?
    /// The bytes of the last frame this Mac sealed, so a test can send them twice.
    private var lastFrame: Data?

    /// A Mac showing a pairing code, or one that only knows the devices it has paired with.
    init(
        identity: DeviceIdentity = DeviceIdentity(), pairingSecret: Data? = nil,
        known: [DevicePublicKeys] = []
    ) {
        self.identity = identity
        self.secret = pairingSecret
        self.known = Set(known.map(\.keyAgreement))
    }

    /// What a pairing code publishes about this Mac.
    var publicKeys: DevicePublicKeys { identity.publicKeys }

    /// Starts serving one road.
    func serve(_ road: any LinkConnection) {
        self.road = road
        responder = HandshakeResponder(
            identity: identity, isKnown: { [known] keys in known.contains(keys.keyAgreement) },
            pairingSecret: secret)
        let frames = road.frames()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await bytes in frames { await self.receive(bytes) }
            } catch {
                // The phone went; there is nothing left to answer.
            }
        }
    }

    /// Stops serving.
    func stop() async {
        task?.cancel()
        await road?.close()
    }

    /// Says something to the phone that nothing asked for: a snapshot, a delta, a refusal.
    func announce<T: Encodable>(_ value: T, kind: MessageKind) async throws {
        try await send(.envelope(Envelope.encoding(value, kind: kind)))
    }

    /// One frame from the phone: plaintext while the handshake runs, sealed after it.
    private func receive(_ bytes: Data) async {
        do {
            guard let channel else { return try await handshake(bytes) }
            switch try channel.open(bytes).frame {
            case .envelope(let envelope): try await answer(envelope)
            case .chunk(let piece): chunk(piece)
            }
        } catch {
            try? await plaintext(Envelope.encoding(asLinkError(error), kind: .error))
        }
    }

    /// One of the three plaintext messages.
    private func handshake(_ bytes: Data) async throws {
        guard case .envelope(let envelope) = try FrameCodec.decode(bytes),
            let responder
        else { return }
        switch envelope.kind {
        case .hello:
            let accept = try responder.receive(try envelope.decode(Hello.self))
            try await plaintext(Envelope.encoding(accept, kind: .accept))
        case .confirm:
            let (channel, peer, paired) = try responder.receive(try envelope.decode(Confirm.self))
            if paired { known.insert(peer.keyAgreement) }
            self.channel = channel
        default:
            break
        }
    }

    /// A message the phone sent over the sealed channel.
    private func answer(_ envelope: Envelope) async throws {
        if envelope.kind == .blobStart {
            let start = try envelope.decode(BlobStart.self)
            assembling[start.blobID] = BlobReassembly(
                blobID: start.blobID, byteCount: start.byteCount)
            return
        }
        guard envelope.kind == .request else { return }
        let command = try envelope.decode(Command.self)
        commands.append(command)
        let answer = reply ?? standing(for: command)
        try await send(.envelope(Envelope.encoding(answer, kind: .reply, inReplyTo: envelope.id)))
        if case .blob(let start) = answer, let payload {
            for piece in BlobChunker.chunks(of: payload, blobID: start.blobID) {
                try await send(.chunk(piece))
            }
        }
    }

    /// What this Mac answers a command with when the test has not said.
    private func standing(for command: Command) -> Reply {
        switch command {
        case .fetchThumbnail, .fetchFile:
            guard let payload else {
                return .error(LinkError(code: .notFound, reason: "There is no such picture."))
            }
            return .blob(BlobStart(byteCount: payload.count, mime: "image/png"))
        case .enqueue:
            return .queued(batchID: UUID())
        default:
            return .ok
        }
    }

    /// One piece of a blob the phone is sending, which it announced first.
    private func chunk(_ piece: BlobChunk) {
        guard var assembly = assembling[piece.blobID] else { return }
        guard let whole = try? assembly.accept(piece) else {
            assembling[piece.blobID] = assembly
            return
        }
        assembling[piece.blobID] = nil
        blobs.append(whole)
    }

    /// Sends the last frame again, which is what a relay that replayed an invocation does.
    func repeatLastFrame() async throws {
        guard let lastFrame, let road else { throw LinkClientTestError.noSession }
        try await road.send(lastFrame)
    }

    private func send(_ frame: Frame) async throws {
        guard let channel, let road else { throw LinkClientTestError.noSession }
        let bytes = try channel.seal(frame)
        lastFrame = bytes
        try await road.send(bytes)
    }

    private func plaintext(_ envelope: Envelope) async throws {
        guard let road else { throw LinkClientTestError.noSession }
        try await road.send(try FrameCodec.encode(.envelope(envelope)))
    }

    private func asLinkError(_ error: any Error) -> LinkError {
        (error as? LinkError) ?? LinkError(code: .badRequest, reason: "The Mac could not read that.")
    }
}

/// The one way the fake Mac fails on its own.
enum LinkClientTestError: Error {
    case noSession
}
