import Foundation
import ZephraLinkProtocol

/// The three plaintext messages, and the reader that runs for the rest of the session.
extension LinkClient {
    /// Runs the handshake over an open road and leaves the session live.
    ///
    /// The reader starts before the first message goes out, not after the handshake: the Mac's
    /// answer can be on its way back before this end asks for it, and a frame read by nobody is
    /// a handshake that hangs. Until `channel` is set, a frame read is one of the plaintext
    /// three and is handed to whoever is waiting for it.
    func openSession(
        over road: any LinkConnection, kind: LinkRoad, peer: DevicePublicKeys, secret: Data?
    ) async throws {
        let session = LinkSession(road: road, kind: kind)
        self.session = session
        let frames = road.frames()
        session.reader = Task { [weak self] in await self?.read(frames, for: session) }
        connection = .handshaking(kind)
        let initiator = HandshakeInitiator(
            identity: identity, peer: peer, pairingSecret: secret, deviceName: deviceName)
        try await sendPlaintext(Envelope.encoding(initiator.hello(), kind: .hello), over: road)
        let accept = try await plaintext(Accept.self, kind: .accept, from: session)
        let (confirm, channel) = try initiator.receive(accept)
        try await sendPlaintext(Envelope.encoding(confirm, kind: .confirm), over: road)
        session.channel = channel
        session.inbox = inbox(over: channel, for: session)
        connection = .live(kind)
    }

    /// The inbox this session reads through, with the answer to a gap it could not fill.
    ///
    /// Loss is the end of the session: a frame that never arrived cannot be asked for again, and
    /// the phone's own reconnection is the recovery — it opens a new channel, and the first thing
    /// a new channel carries is a snapshot of the whole state.
    private func inbox(over channel: SecureChannel, for session: LinkSession) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: frameHold)
        inbox.onLoss { [weak self, weak session] in
            Task { @MainActor in
                guard let self, let session else { return }
                await self.lost(session)
            }
        }
        return inbox
    }

    /// A gap the Mac's stream never filled. The road is still open, but what it carries is no
    /// longer the stream that started, so the session goes and the phone reconnects.
    func lost(_ session: LinkSession) async {
        logger.error("A frame was lost on the way here; the session is finished.")
        await roadEnded(session, error: LinkClientError.notConnected)
    }

    /// Every frame one road carries, until it stops.
    private func read(_ frames: AsyncThrowingStream<Data, Error>, for session: LinkSession) async {
        do {
            for try await bytes in frames {
                guard self.session === session else { return }
                await receive(bytes, for: session)
            }
            await roadEnded(session, error: nil)
        } catch {
            await roadEnded(session, error: error)
        }
    }

    /// One frame: plaintext while the handshake runs, sealed after it.
    ///
    /// A frame the inbox refuses as late or as too far ahead is dropped with a line in the log,
    /// never a closed session: the relay is several concurrent invocations and a duplicate or an
    /// overtaken frame is ordinary. A frame that will not authenticate still ends it.
    private func receive(_ bytes: Data, for session: LinkSession) async {
        guard let inbox = session.inbox else { return session.deliverPlaintext(bytes) }
        do {
            for frame in try inbox.accept(bytes) { dispatch(frame) }
        } catch SecureChannelError.replayed, SecureChannelError.outOfWindow {
            logger.notice("A frame arrived late or too far ahead and was dropped.")
        } catch {
            logger.error("A frame did not open; the channel is finished.")
            await roadEnded(session, error: error)
        }
    }

    /// The road stopped, from the far end or from a frame that did not authenticate.
    private func roadEnded(_ session: LinkSession, error: (any Error)?) async {
        guard self.session === session else { return }
        self.session = nil
        preview = nil
        settleEverything(with: error ?? LinkClientError.notConnected)
        await session.end(error ?? LinkClientError.notConnected)
        connection = error.map { .failed(Self.words(for: $0, host: pairedHost?.name ?? "the Mac")) }
            ?? .offline
    }

    /// The next plaintext message, as the type that kind carries.
    private func plaintext<T: Decodable>(
        _ type: T.Type, kind: MessageKind, from session: LinkSession
    ) async throws -> T {
        guard case .envelope(let envelope) = try FrameCodec.decode(try await session.nextPlaintext())
        else { throw LinkClientError.unexpectedMessage(kind: "chunk") }
        if envelope.kind == .error { throw try envelope.decode(LinkError.self) }
        guard envelope.kind == kind else {
            throw LinkClientError.unexpectedMessage(kind: envelope.kind.rawValue)
        }
        return try envelope.decode(type)
    }

    /// One envelope out with no channel over it, which only the handshake ever sends.
    private func sendPlaintext(_ envelope: Envelope, over road: any LinkConnection) async throws {
        try await road.send(try FrameCodec.encode(.envelope(envelope)))
    }
}
