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
    var silentOffers = false
    var silentPreviews = false
    /// The pictures this Mac's folder holds, newest first, which `libraryPage` windows onto.
    var library: [LibraryEntry] = []
    /// How many of the next page requests are refused, for the retry a dropped page takes.
    var refusesPages = 0
    /// Called as each command arrives, before it is answered, so a test can ask what the phone
    /// was holding at the moment it asked for the next page.
    var onCommand: (@MainActor (Command) -> Void)?
    var afterReply: (@MainActor (Command) async throws -> Void)?
    /// The state a `resync` is answered with, behind its `.ok`. Nil for a Mac that answers the
    /// command and sends nothing after it.
    var world: StateSnapshot?
    /// A Mac too old to know `fromChunk`, which sends the whole file however far in it was asked
    /// to start.
    var ignoresFromChunk = false
    /// The chunk each `fetchFile` asked to start at, in the order they were asked.
    private(set) var sentFromChunk: [UInt32] = []
    /// Whether a ping is answered, as the real Mac always answers one. False is a Mac that has
    /// gone quiet on a socket nobody has closed, which is what a probe is for.
    var answersPings = true

    private var secret: Data?
    private var known: Set<Data>
    private var road: (any LinkConnection)?
    private var responder: HandshakeResponder?
    var isAuthenticated: Bool { channel != nil }
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
        if envelope.kind == .ping {
            guard answersPings else { return }
            return try await send(
                .envelope(Envelope(kind: .pong, inReplyTo: envelope.id, body: Data("{}".utf8))))
        }
        guard envelope.kind == .request else { return }
        let command = try envelope.decode(Command.self)
        commands.append(command)
        onCommand?(command)
        if silentOffers, case .multiHost(.offer) = command { return }
        if silentPreviews, case .multiHost(.previews) = command { return }
        let answer = reply ?? standing(for: command)
        try await send(.envelope(Envelope.encoding(answer, kind: .reply, inReplyTo: envelope.id)))
        try await afterReply?(command)
        // The `.ok` first and the snapshot behind it, which is the order the Mac answers in.
        if command == .resync, let world {
            try await send(.envelope(Envelope.encoding(world, kind: .snapshot)))
        }
        if case .blob(let start) = answer, let payload {
            // The whole file, minus what the phone said it already holds. The announcement still
            // names the whole of it, which is what the phone completes against.
            let pieces = BlobChunker.chunks(of: payload, blobID: start.blobID)
            let from = ignoresFromChunk ? 0 : Int(Self.fromChunk(of: command))
            sentFromChunk.append(Self.fromChunk(of: command))
            for piece in pieces.dropFirst(from < pieces.count ? from : 0) {
                try await send(.chunk(piece))
            }
        }
    }

    /// Where a command asked the file to start, which is zero for anything but a `fetchFile`.
    private static func fromChunk(of command: Command) -> UInt32 {
        guard case .fetchFile(_, let from) = command else { return 0 }
        return from
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
        case .multiHost(.listing(let offset, let limit, let expected)):
            let revision = GenerationInput.digest((try? LinkJSON.encode(library)) ?? Data())
            if let expected, expected != revision {
                return .error(LinkError(code: .busy, reason: "The library changed."))
            }
            return .multiHost(.listing(LibraryListing(revision: revision, page: page(offset: offset, limit: limit))))
        case .libraryPage(let offset, let limit):
            guard refusesPages == 0 else {
                refusesPages -= 1
                return .error(LinkError(code: .busy, reason: "Not just now."))
            }
            return .entries(page(offset: offset, limit: limit))
        default:
            return .ok
        }
    }

    /// One window onto this Mac's folder, clamped the way the real one clamps it.
    private func page(offset: Int, limit: Int) -> LibraryPage {
        let start = min(max(offset, 0), library.count)
        let end = min(start + min(max(limit, 0), 200), library.count)
        return LibraryPage(entries: Array(library[start..<end]), offset: start, total: library.count)
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
