import Foundation
import ZephraLinkProtocol

/// The other end of the link, as a test drives it.
///
/// Everything a real phone would do and nothing it would draw: a `HandshakeInitiator`, a channel,
/// and a list of everything the Mac has said. It reads on a task of its own and records, so a
/// test asks "what has arrived" rather than having to be at the right await when it does.
@MainActor
final class FakePhone {
    /// This phone's long-lived keys, so a second connection is the same device.
    let identity: DeviceIdentity
    /// What it calls itself in its `Hello`.
    let deviceName: String
    /// Everything sealed that has arrived, in order.
    private(set) var envelopes: [Envelope] = []
    /// Chunks, by the blob they belong to.
    private(set) var chunks: [UUID: [BlobChunk]] = [:]
    /// Why the connection ended, when it ended badly.
    private(set) var failure: (any Error)?

    private let connection: any LinkConnection
    private var initiator: HandshakeInitiator?
    private var channel: SecureChannel?
    /// What the Mac says, in the order it sealed it, as a real phone reads it.
    private var inbox: OrderedInbox?
    private var reader: Task<Void, Never>?

    /// A phone over one end of a road.
    init(
        connection: any LinkConnection,
        identity: DeviceIdentity = DeviceIdentity(),
        deviceName: String = "A Test iPhone"
    ) {
        self.connection = connection
        self.identity = identity
        self.deviceName = deviceName
    }

    /// Opens the handshake with one Mac and waits until the channel is up.
    ///
    /// `pairingSecret` is the one out of a QR code on a first connection and nil on every
    /// reconnection, where the static keys the two ends already share stand in for one.
    func connect(to peer: DevicePublicKeys, pairingSecret: Data? = nil) async throws {
        let initiator = HandshakeInitiator(
            identity: identity, peer: peer, pairingSecret: pairingSecret, deviceName: deviceName)
        self.initiator = initiator
        startReading()
        try await sendPlaintext(initiator.hello(), kind: .hello)
        // Either answer closes the wait: a Mac that will not talk to this device says so in the
        // clear and closes, and waiting for an `accept` that is never coming would make every
        // refusal cost the whole of `patience`.
        let answer = try await waitFor { [weak self] in
            self?.envelopes.first { $0.kind == .accept || $0.kind == .error }
        }
        guard answer.kind == .accept else { throw try answer.decode(LinkError.self) }
        let opened = try initiator.receive(try answer.decode(Accept.self))
        // The channel is set first and the confirm still goes in the clear: it is the last of
        // the three plaintext messages, and everything after it is sealed.
        channel = opened.channel
        inbox = OrderedInbox(channel: opened.channel)
        try await sendPlaintext(opened.confirm, kind: .confirm)
    }

    /// Answers a code on screen with a guess: the whole handshake, with a `confirm` that proves
    /// nothing.
    ///
    /// A real phone holding the wrong secret stops at the Mac's own tag and never sends a
    /// confirm at all, so it is no use for asking what a Mac does with wrong answers. Something
    /// working through a code sends one anyway, and this is that.
    func guessTheCode(of peer: DevicePublicKeys) async throws {
        let initiator = HandshakeInitiator(
            identity: identity, peer: peer,
            pairingSecret: Data(repeating: 0xEE, count: PairingSecret.byteCount),
            deviceName: deviceName)
        self.initiator = initiator
        startReading()
        try await sendPlaintext(initiator.hello(), kind: .hello)
        let answer = try await waitFor { [weak self] in
            self?.envelopes.first { $0.kind == .accept || $0.kind == .error }
        }
        guard answer.kind == .accept else { throw try answer.decode(LinkError.self) }
        try await sendPlaintext(Confirm(tag: Data(repeating: 0x5A, count: 32)), kind: .confirm)
    }

    /// Closes this end of the road.
    func disconnect() async {
        reader?.cancel()
        await connection.close()
    }

    /// One sealed message out.
    func send(_ value: some Encodable, kind: MessageKind, inReplyTo: UUID? = nil) async throws {
        try await send(envelope: try Envelope.encoding(value, kind: kind, inReplyTo: inReplyTo))
    }

    /// One sealed message whose identity the caller already knows, which is how a request is
    /// matched to its reply.
    func send(envelope: Envelope) async throws {
        try await send(.envelope(envelope))
    }

    /// One sealed frame out, for the chunks of a picture on its way to the Mac.
    func send(_ frame: Frame) async throws {
        guard let channel else { throw LinkFailure.notConnected }
        try await connection.send(try channel.seal(frame))
    }

    /// Seals these frames in the order given and puts them on the road in another, which is what
    /// the relay's concurrent invocations do to a run of them.
    func send(_ frames: [Frame], arrivingAs order: [Int]) async throws {
        guard let channel else { throw LinkFailure.notConnected }
        let sealed = try frames.map { try channel.seal($0) }
        for index in order { try await connection.send(sealed[index]) }
    }

    /// One plaintext message out, which is only ever a handshake message.
    private func sendPlaintext(_ value: some Encodable, kind: MessageKind) async throws {
        try await connection.send(
            try FrameCodec.encode(.envelope(try Envelope.encoding(value, kind: kind))))
    }

    /// Reads until the road closes, opening what it can and recording everything.
    private func startReading() {
        reader = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await data in connection.frames() {
                    guard let inbox else {
                        try record(try FrameCodec.decode(data))
                        continue
                    }
                    for frame in try inbox.accept(data) { try record(frame) }
                }
            } catch {
                failure = error
            }
        }
    }

    private func record(_ frame: Frame) throws {
        switch frame {
        case .envelope(let envelope): envelopes.append(envelope)
        case .chunk(let chunk): chunks[chunk.blobID, default: []].append(chunk)
        }
    }

    /// The one way this phone fails on its own account.
    enum LinkFailure: Error { case notConnected, timedOut }
}
