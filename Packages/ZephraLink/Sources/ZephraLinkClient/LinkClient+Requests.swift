import Foundation
import ZephraLinkProtocol

/// Asking the Mac for something and holding the request open until it answers.
extension LinkClient {
    /// Sends one command and waits for its reply.
    ///
    /// Every command gets exactly one reply, a refusal included, so a request can be held open
    /// and known to close. The timeout is this end's own promise: a Mac that went to sleep mid
    /// request would otherwise leave a view spinning for as long as the app runs.
    public func request(_ command: Command) async throws -> Reply {
        if isFrozen { return .ok }
        guard session?.channel != nil else { throw LinkClientError.notConnected }
        let envelope = try Envelope.encoding(command, kind: .request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[envelope.id] = continuation
            timers[envelope.id] = expire(envelope.id, after: LinkClient.requestTimeout)
            // Sealed and queued here rather than on a task of its own: the counter a frame is
            // sealed under is its position in the stream, and a task per request is two requests
            // taking two counters and reaching the socket in whichever order they are scheduled.
            do { try send(.envelope(envelope)) } catch { fail(envelope.id, with: error) }
        }
    }

    /// One sealed frame out, through the session's one writer.
    func send(_ frame: Frame) throws {
        guard let session else { throw LinkClientError.notConnected }
        try session.send(frame)
    }

    /// The reply to one request, which is what closes it.
    func answer(_ id: UUID, with reply: Reply) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(returning: reply)
    }

    /// A request that will not be answered, because sending it failed or time ran out.
    func fail(_ id: UUID, with error: any Error) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
        blobWaiters.removeValue(forKey: id)?.resume(throwing: error)
        blobs.removeValue(forKey: id)
        blobOrder.removeAll { $0 == id }
        arrivedBlobs.removeValue(forKey: id)
    }

    /// Everything waiting, told the session is over.
    func settleEverything(with error: any Error) {
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        let waiting = pending.values
        let blobbed = blobWaiters.values
        pending.removeAll()
        blobWaiters.removeAll()
        blobs.removeAll()
        blobOrder.removeAll()
        arrivedBlobs.removeAll()
        for continuation in waiting { continuation.resume(throwing: error) }
        for continuation in blobbed { continuation.resume(throwing: error) }
    }

    /// The task that gives up on one request or one blob.
    func expire(_ id: UUID, after delay: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.fail(id, with: LinkClientError.timedOut)
        }
    }
}
