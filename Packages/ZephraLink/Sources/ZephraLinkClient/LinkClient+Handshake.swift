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
        let events = road.peerEvents()
        session.peers = Task { [weak self] in await self?.watch(events, for: session) }
        let refusals = road.relayErrors()
        session.roadErrors = Task { [weak self] in await self?.watch(refusals) }
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
    /// A gap is no longer the end of the session. A frame that never arrived cannot be asked for
    /// again, but the *world* can: the phone steps over the hole, throws away everything the
    /// missing frame might have been part of, and sends `resync`, which the Mac answers with a
    /// fresh snapshot. Ending the session instead meant a reconnection, and over a run that
    /// dropped a frame every few seconds it meant reconnecting until the phone gave up.
    private func inbox(over channel: SecureChannel, for session: LinkSession) -> OrderedInbox {
        let inbox = OrderedInbox(channel: channel, hold: frameHold)
        inbox.onGap { [weak self, weak session] gap, frames in
            Task { @MainActor in
                guard let self, let session else { return }
                await self.lost(session, gap: gap, releasing: frames)
            }
        }
        return inbox
    }

    /// A gap the Mac's stream never filled, stepped over.
    ///
    /// At error and with the counters: a skip is rare, costs a whole resync, and is the first
    /// thing to look for when the phone behaves oddly. What the hole may have swallowed is a
    /// blob's chunk and a reply, so every transfer in flight is dropped and every request still
    /// open is failed as `lost` — both of which the caller retries once — and then the state the
    /// deltas were editing is asked for again, whole.
    func lost(_ session: LinkSession, gap: FrameGap, releasing frames: [Frame]) async {
        logger.error(
            "A frame never arrived (\(gap.summary, privacy: .public)); asking the Mac for the world again."
        )
        settleEverything(with: LinkClientError.lost)
        resync()
        for frame in frames { dispatch(frame) }
    }

    /// Asks the Mac for the whole of its state again. Answered `.ok` and then a fresh snapshot,
    /// which is what puts the phone back in step — the library pull included, since it restarts
    /// on a snapshot landing.
    private func resync() {
        do {
            try send(.envelope(try Envelope.encoding(Command.resync, kind: .request)))
        } catch {
            logger.error(
                "The resync did not go out: \(String(describing: error), privacy: .public)")
        }
    }

    /// The road's own refusals, which over the relay is the one place a frame vanishes with
    /// nobody above it any the wiser. Logged at error and nothing else: the Mac is short one
    /// frame, which is a gap it steps over and a resync this end will be asked for anyway.
    private func watch(_ refusals: AsyncStream<String>) async {
        for await reason in refusals {
            logger.error(
                "The relay refused a frame on its way to the Mac: \(reason, privacy: .public)")
        }
    }

    /// The road saying the Mac arrived or went, for as long as it can say.
    ///
    /// A `left` is the end of the session and not a hint: over the relay the Mac's own socket is
    /// gone, so the room has nobody in it and every request on this channel would sit until it
    /// timed out. Ending here also wakes the reconnection, which opens a road to whichever
    /// listener the Mac has rejoined with.
    private func watch(
        _ events: AsyncStream<RelayPeerEvent>, for session: LinkSession
    ) async {
        for await event in events where event == .left {
            guard self.session === session else { return }
            logger.notice("The Mac left the room; the session is finished.")
            return await roadEnded(session, error: nil)
        }
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
        sessionEnded()
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
