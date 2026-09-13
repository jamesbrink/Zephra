import Foundation
import ZephraLinkProtocol

/// Everything that leaves the Mac, in one place.
///
/// Each of these seals at the call and hands the bytes to the writer, which is what keeps the
/// channel's counter in step: a frame's nonce is its position in the stream, so the order frames
/// are sealed in must be the order they go out in, and a single stream drained by one task is
/// the cheapest way to say that.
extension CompanionSession {
    /// One sealed frame.
    func send(_ frame: Frame) throws {
        guard let channel else {
            throw LinkError(code: .refused, reason: "That device has not finished connecting.")
        }
        enqueue(try channel.seal(frame))
    }

    /// One sealed message carrying `value`.
    func send(_ value: some Encodable, kind: MessageKind, inReplyTo: UUID? = nil) throws {
        try send(.envelope(try Envelope.encoding(value, kind: kind, inReplyTo: inReplyTo)))
    }

    /// One plaintext message, which is only ever a handshake message or a refusal before the
    /// channel exists.
    func sendPlaintext(_ value: some Encodable, kind: MessageKind) throws {
        enqueue(try FrameCodec.encode(
            .envelope(try Envelope.encoding(value, kind: kind))))
    }

    /// The answer to one request.
    func reply(_ reply: Reply, to request: UUID) throws {
        try send(reply, kind: .reply, inReplyTo: request)
    }

    /// A refusal, sealed once there is a channel and in the clear before there is one — which is
    /// how a device refused at the handshake is told why rather than left waiting.
    func sendError(_ error: LinkError, inReplyTo: UUID? = nil) throws {
        if channel == nil {
            try sendPlaintext(error, kind: .error)
        } else {
            try send(error, kind: .error, inReplyTo: inReplyTo)
        }
    }

    /// One change to the state the phone is holding. Silent on a closed channel: a session on
    /// its way down is not a failure the observation loop should have to know about.
    func send(_ delta: StateDelta) {
        if case .engine(let engine) = delta, !engine.isBusy { pendingPreview = nil }
        if case .running = delta { pendingPreview = nil }
        guard isReady else { return }
        try? send(delta, kind: .delta)
    }

    /// One frame of the run in flight, for the same reason and with the same silence.
    func send(_ frame: PreviewFrameDTO) {
        guard isReady, wantsPreviews, !isClosed else { return }
        pendingPreview = frame
        flushPreview()
    }
    func flushPreview() {
        guard wantsPreviews, isReady, !isClosed else { pendingPreview = nil; return }
        guard queuedBytes < 262_144, let frame = pendingPreview else { return }
        pendingPreview = nil
        try? send(frame, kind: .preview)
    }
}
