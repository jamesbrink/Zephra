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
            Task { [weak self] in
                guard let self else { return }
                do { try await self.send(.envelope(envelope)) } catch {
                    self.fail(envelope.id, with: error)
                }
            }
        }
    }

    /// One sealed frame out.
    func send(_ frame: Frame) async throws {
        guard let session, let channel = session.channel else { throw LinkClientError.notConnected }
        let bytes = try channel.seal(frame)
        try await session.road.send(bytes)
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
