import Foundation
import ZephraLinkProtocol

/// Asking the Mac for things, and waiting for what it says back.
///
/// Polling rather than continuations: a test wants "this has arrived by now", and a suite built
/// on a barrier per message would have to name every message the Mac sends unprompted — the
/// snapshot, a dozen deltas, a preview frame — just to get to the reply it cares about.
extension FakePhone {
    /// How long any of these will wait before the test fails on its own terms.
    static let patience = Duration.seconds(5)

    /// The snapshot every session opens with.
    func snapshot() async throws -> StateSnapshot {
        try await waitForBody(kind: .snapshot)
    }

    /// Every change the Mac has published so far.
    func deltas() throws -> [StateDelta] {
        try envelopes.filter { $0.kind == .delta }.map { try $0.decode(StateDelta.self) }
    }

    /// Every preview frame it has sent.
    func previews() throws -> [PreviewFrameDTO] {
        try envelopes.filter { $0.kind == .preview }.map { try $0.decode(PreviewFrameDTO.self) }
    }

    /// Every unsolicited refusal, which is how a handshake failure and a revocation arrive.
    func errors() throws -> [LinkError] {
        try envelopes.filter { $0.kind == .error }.map { try $0.decode(LinkError.self) }
    }

    /// Sends one command and waits for its one reply.
    @discardableResult
    func request(_ command: Command) async throws -> Reply {
        let envelope = try Envelope.encoding(command, kind: .request)
        try await send(envelope: envelope)
        let answer = try await waitFor { [weak self] in
            self?.envelopes.first { $0.kind == .reply && $0.inReplyTo == envelope.id }
        }
        return try answer.decode(Reply.self)
    }

    /// The bytes behind a `blob` reply, once every chunk of it has landed.
    func blob(_ start: BlobStart) async throws -> Data {
        let pieces = try await waitFor { [weak self] () -> [BlobChunk]? in
            guard let all = self?.chunks[start.blobID], let first = all.first,
                all.count == Int(first.count)
            else { return nil }
            return all
        }
        var assembly = BlobReassembly(blobID: start.blobID, byteCount: start.byteCount)
        for chunk in pieces {
            if let whole = try assembly.accept(chunk) { return whole }
        }
        throw LinkFailure.timedOut
    }

    /// Sends a picture to the Mac as a blob, and answers the id an `enqueue` should name.
    func sendPicture(_ data: Data) async throws -> UUID {
        let start = BlobStart(byteCount: data.count, mime: "image/png")
        try await send(start, kind: .blobStart)
        for chunk in BlobChunker.chunks(of: data, blobID: start.blobID) {
            try await send(.chunk(chunk))
        }
        return start.blobID
    }

    /// The body of the first message of `kind` to arrive.
    func waitForBody<T: Decodable>(kind: MessageKind) async throws -> T {
        try await waitFor { [weak self] in self?.envelopes.first { $0.kind == kind } }
            .decode(T.self)
    }

    /// Polls until `answer` has one, and throws when patience runs out.
    func waitFor<T>(_ answer: () -> T?) async throws -> T {
        let deadline = ContinuousClock.now + Self.patience
        while ContinuousClock.now < deadline {
            if let found = answer() { return found }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw LinkFailure.timedOut
    }
}
