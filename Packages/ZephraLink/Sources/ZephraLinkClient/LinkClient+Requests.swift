import Foundation
import ZephraLinkProtocol

/// Asking the Mac for something and holding the request open until it answers.
extension LinkClient {
    /// Sends one command and waits for its reply, asking once more if the first attempt went
    /// missing.
    ///
    /// Every command gets exactly one reply, a refusal included, so a request can be held open
    /// and known to close. The timeout is this end's own promise: a Mac that went to sleep mid
    /// request would otherwise leave a view spinning for as long as the app runs.
    ///
    /// A reply lost to a hole in the stream, or one that never came, is asked for again under a
    /// **fresh id** — the first envelope may yet turn up, and two requests sharing an id would be
    /// two answers to one continuation. Commands other than `upscale` are safe to repeat: the queue commands,
    /// the library edits and the fetches all say what the Mac should end up like rather than
    /// counting what it is asked. The one that cannot is `enqueue`, whose repeat the Mac answers
    /// with the run it already made, keyed by `GenerationRequest.requestID`. Upscale has no
    /// deduplication key on older Macs and is sent only once.
    public func request(_ command: Command) async throws -> Reply {
        if isFrozen {
            if case .workflow(let work) = command { return frozenWorkflow(work) }
            return .ok
        }
        if case .upscale = command { return try await ask(command) }
        do {
            return try await ask(command)
        } catch let error as LinkClientError where error.isWorthRepeating {
            logger.notice(
                "A \(command.kind.rawValue, privacy: .public) went unanswered; asking once more.")
            return try await ask(command)
        }
    }

    /// One attempt at one command, under an envelope id of its own.
    ///
    /// `beforeSending` is handed that id before anything can answer it, which is how a transfer
    /// that is carrying on from where it got to says so: the reply's announcement is opened on
    /// this same actor and needs to find what it is resuming already filed under the id it is a
    /// reply to.
    func ask(_ command: Command, timeout: Duration? = nil, beforeSending: (UUID) -> Void = { _ in }) async throws -> Reply {
        guard session?.channel != nil else { throw LinkClientError.notConnected }
        let envelope = try Envelope.encoding(command, kind: .request)
        beforeSending(envelope.id)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
            pending[envelope.id] = continuation
            timers[envelope.id] = expire(envelope.id, after: timeout ?? requestTimeout)
            // Sealed and queued here rather than on a task of its own: the counter a frame is
            // sealed under is its position in the stream, and a task per request is two requests
            // taking two counters and reaching the socket in whichever order they are scheduled.
            do { try send(.envelope(envelope)) } catch { fail(envelope.id, with: error) }
            }
        } onCancel: {
            Task { @MainActor in self.fail(envelope.id, with: CancellationError()) }
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
        resumptions.removeValue(forKey: id)
        // What the transfer got to is kept for whoever asks again, so the next attempt asks for
        // the tail rather than the whole file — but only for a transfer this phone asked for,
        // since that is the only one anybody will ever come back for. A Mac announcing
        // unsolicited blobs and sending a chunk of each would otherwise park a partial apiece
        // until the session ended.
        let assembly = blobs.removeValue(forKey: id)
        if wantedBlobs.remove(id) != nil, let assembly, var resumption = BlobResumption(assembly) {
            resumption.budgetID = id
            salvaged[id] = resumption
        } else { blobBudget.release(owner: transferOwner, blob: id) }
        blobWaiters.removeValue(forKey: id)?.resume(throwing: error)
        blobOrder.removeAll { $0 == id }
        arrivedBlobs.removeValue(forKey: id)
    }

    /// Everything waiting, told the session is over.
    ///
    /// For a session that has actually ended — the road going, or the phone letting the Mac go —
    /// and not for a gap: a hole in the stream swallows one message, and the transfer or the
    /// request it swallowed is the one that pays for it.
    func settleEverything(with error: any Error) {
        for id in Set(blobs.keys).union(arrivedBlobs.keys).union(salvaged.keys) {
            blobBudget.release(owner: transferOwner, blob: id)
        }
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        let waiting = pending.values
        let blobbed = blobWaiters.values
        pending.removeAll()
        blobWaiters.removeAll()
        blobs.removeAll()
        blobOrder.removeAll()
        wantedBlobs.removeAll()
        arrivedBlobs.removeAll()
        salvaged.removeAll()
        resumptions.removeAll()
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
