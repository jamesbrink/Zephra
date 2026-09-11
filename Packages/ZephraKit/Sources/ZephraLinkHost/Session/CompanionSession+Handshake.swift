import Foundation
import ZephraLinkProtocol

/// The three plaintext messages, and everything that arrives after them.
///
/// One loop over the connection's frames rather than a handshake that reads its own two messages
/// and hands the iterator on: the channel is what says which stage the session is in — nil means
/// the handshake is still going — so there is one reader, one place a frame is decided about, and
/// no iterator to pass between isolation domains.
///
/// The responder decides who may talk before it derives any key, and what it decides with is a
/// snapshot of the paired devices taken as the `Hello` lands: the check runs inside
/// `HandshakeResponder` as a `@Sendable` closure, and a closure that reached back into the host
/// would be reading main-actor state from wherever CryptoKit happened to call it.
extension CompanionSession {
    /// The whole life of the session: frames in until the road closes.
    func run() async {
        do {
            for try await data in connection.frames() {
                guard !isClosed else { break }
                try await receive(data)
            }
            await close()
        } catch let error as LinkError {
            await close(telling: error)
        } catch {
            await close()
        }
    }

    /// One frame, sealed once there is a channel and plaintext before there is one.
    ///
    /// A frame the inbox refuses as late or as too far ahead is dropped with a line in the log,
    /// never a closed session: the relay is several concurrent invocations and a duplicate or an
    /// overtaken frame is ordinary. A gap the inbox waited out is stepped over, and the frames
    /// behind it arrive through `stepOver`. What still ends the session is a frame that will not
    /// authenticate, which arrives here as a throw.
    private func receive(_ data: Data) async throws {
        guard let inbox else { return try await handshake(data) }
        let ready: [Frame]
        do {
            ready = try inbox.accept(data)
        } catch SecureChannelError.replayed, SecureChannelError.outOfWindow {
            host?.logger.notice("companion dropped a frame that arrived late or too far ahead")
            return
        }
        for frame in ready { try await receive(frame) }
    }

    /// A handshake message: `hello` first, `confirm` second, nothing else.
    private func handshake(_ data: Data) async throws {
        guard case .envelope(let envelope) = try FrameCodec.decode(data) else {
            throw LinkError(code: .badRequest, reason: "That device did not open the connection properly.")
        }
        switch envelope.kind {
        case .hello: try receive(hello: try envelope.decode(Hello.self))
        case .confirm: try await receive(confirm: try envelope.decode(Confirm.self))
        default:
            throw LinkError(code: .badRequest, reason: "That device did not open the connection properly.")
        }
    }

    /// The opening message: answered with an `accept`, or refused before any key is derived.
    private func receive(hello: Hello) throws {
        guard responder == nil, let host else {
            throw LinkError(code: .badRequest, reason: "That device has already said hello.")
        }
        let known = Set(host.devices.map(\.keys))
        let responder = HandshakeResponder(
            identity: host.identity,
            isKnown: { known.contains($0) },
            pairingSecret: host.liveSecret)
        let accept = try responder.receive(hello)
        self.responder = responder
        isPairingAttempt = hello.pairing
        deviceName = hello.deviceName
        try sendPlaintext(accept, kind: .accept)
    }

    /// The phone's proof. Everything after this is sealed, and the first sealed thing the phone
    /// is sent is the snapshot.
    private func receive(confirm: Confirm) async throws {
        guard let responder, let host else {
            throw LinkError(code: .badRequest, reason: "That device has not said hello yet.")
        }
        let opened: (channel: SecureChannel, peer: DevicePublicKeys, paired: Bool)
        do {
            opened = try responder.receive(confirm)
        } catch {
            // A wrong answer to a code on screen is an answer somebody guessed at.
            if isPairingAttempt { host.pairingFailed() }
            throw error
        }
        channel = opened.channel
        peer = opened.peer
        inbox = makeInbox(over: opened.channel)
        handshakeSettled()
        if opened.paired {
            host.devicePaired(opened.peer, name: deviceName)
        } else {
            host.markSeen(opened.peer)
        }
        try send(
            StateSnapshotProjection.snapshot(
                store: host.store, index: host.index, hostName: host.hostName),
            kind: .snapshot)
        isReady = true
        host.startObserving()
        host.logger.info("companion session open with \(self.deviceName, privacy: .public)")
    }

    /// What arrives once the channel is up.
    ///
    /// A chunk that does not fit its transfer refuses that transfer and nothing more. The
    /// picture is unusable either way — the `enqueue` naming it is answered `notFound` — and a
    /// session closed over one dropped chunk is a phone that reconnects mid-run and loses the
    /// stream it was following.
    func receive(_ frame: Frame) async throws {
        switch frame {
        case .chunk(let chunk):
            do {
                try accept(chunk)
            } catch let error as LinkError {
                incoming = nil
                incomingID = nil
                host?.logger.notice(
                    "companion refused a chunk: \(error.reason, privacy: .public)")
                try? sendError(error)
            }
        case .envelope(let envelope): try await receive(envelope)
        }
    }

    /// One sealed message, by kind. A kind this build does not answer is an error the phone can
    /// show rather than a closed connection: the envelope was well formed, so the stream is fine.
    private func receive(_ envelope: Envelope) async throws {
        switch envelope.kind {
        case .request:
            guard let command = try? envelope.decode(Command.self) else {
                return try reply(
                    .error(LinkError(code: .badRequest, reason: "This Mac could not read that request.")),
                    to: envelope.id)
            }
            await handle(command, id: envelope.id)
        case .blobStart:
            try begin(try envelope.decode(BlobStart.self))
        case .ping:
            try send(.envelope(
                Envelope(kind: .pong, inReplyTo: envelope.id, body: Data("{}".utf8))))
        case .pong:
            break
        default:
            try sendError(
                LinkError(
                    code: .unsupported,
                    reason: "This Mac does not answer \(envelope.kind.rawValue) messages."),
                inReplyTo: envelope.id)
        }
    }
}
