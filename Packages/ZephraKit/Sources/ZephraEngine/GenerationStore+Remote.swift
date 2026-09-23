import Foundation
import ZephraCore

/// The one door a paired device's request comes in through.
///
/// Every other way into the queue is the Mac user's own hand on the keyboard, and each of them
/// moves the capsule to say what is about to run: `generate(count:)` reads `settings` and
/// follows the run, `queueVariation(of:)` replaces `settings` and `descriptor` outright. A
/// request that arrives from a phone must do none of that — the person at the Mac may be
/// halfway through typing a prompt, and a remote submit that overwrote it would be a bug
/// nobody could explain. So `enqueue` takes its settings and its model as arguments and writes
/// nothing back: the capsule (`settings`, `descriptor`, `modelAwaitsGenerate`,
/// `capsuleHoldsPicture`), the canvas (`followsRun`) and the reference ticket
/// (`claimReference`) are all left exactly as they were. The result still enters `history`,
/// the wall and the library the way any queued generation does; it simply never takes the
/// canvas, because `followsRun` was never turned on for it. What a refusal says is
/// `GenerationStore+RemoteRefusals`.
extension GenerationStore {
    /// Whether the engine would take a queued generation right now: start one, or put it
    /// behind the one it is already rendering.
    ///
    /// `canQueue` without the capsule's half of the question. The Mac's own button asks about
    /// the prompt being typed and the picture on its way into the well; a device's request
    /// brings both with it, so what is left is the engine — idle, or working down its queue,
    /// which is a queue one more entry may join. It is `EngineStateDTO.canQueue` on the wire,
    /// stamped by `EngineStateProjection`, so a phone's Generate button and this gate are one
    /// answer rather than two that can disagree.
    public var acceptsQueuedGeneration: Bool {
        guard !deviceLost else { return false }
        return state.acceptsGeneration || isDraining || canLoad(descriptor)
    }

    /// Whether a request from a paired device would be queued right now, and if not, why.
    ///
    /// `settings` and `count` carry defaults so the question can be asked about the Mac alone —
    /// "could this device submit anything at all" — before a request exists to ask it about.
    /// Given both, the answer is exactly what `enqueue` will do with them.
    ///
    /// Unlike `canQueue` this does not wait for a reference picture on its way into the well:
    /// the well is the Mac user's, a remote request carries its own picture in its settings,
    /// and `canQueueVariation(of:)` takes the same view for the same reason.
    public func remoteAdmission(
        for model: ModelDescriptor,
        settings: GenerationSettings? = nil,
        count: Int = 1,
        logging: Bool = true
    ) -> RemoteAdmission {
        // Before everything, the request itself included: no wait and no correction makes a
        // request runnable on a Mac whose GPU has stopped answering it, and what the phone puts
        // under its Generate button is the Mac's own sentence, which says the remedy.
        if deviceLost { return .refused(BackendError.deviceLostSentence) }
        // Then the request, which is the caller's to fix whatever the Mac is doing: telling a
        // phone to wait for a load that will never make its empty prompt runnable helps nobody.
        if let request = badRequest(model, settings, count) { return .badRequest(request) }
        if let busy = busyReason { return .busy(busy) }
        // Not `acceptsQueuedGeneration`, which is asked about the chosen model: a phone may
        // name another, and that model is the one that has to be loadable.
        guard state.acceptsGeneration || isDraining || canLoad(model) else {
            return .refused(state.remoteRefusal)
        }
        // What the Mac has free this minute is worth asking again in a moment, so a run this
        // machine has not the memory for right now is `refused` rather than a bad request.
        // Only with settings in hand: without them there is no size and no length to charge.
        // `logging` is false for a multi-host offer's pre-check, which is an estimate rather
        // than a decision and would otherwise log every few seconds while nothing runs.
        if let settings, let shortfall = runShortfall(for: model, settings: settings, logging: logging) {
            return .refused(shortfall.sentence)
        }
        return .admitted
    }

    /// Queues `count` generations of `settings` on `model` without touching the capsule
    /// (`settings`, `descriptor`), the canvas (`followsRun`, `capsuleHoldsPicture`) or the
    /// reference ticket. Returns the batch id, or nil when `remoteAdmission` refuses.
    ///
    /// The expansion is `generate(count:)`'s: the first entry runs the seed it was handed, so a
    /// device asking for the same seed twice gets the same picture twice, and the rest take
    /// fresh ones. `GenerationSettings` carries no model of its own, so there is no other
    /// family's schedule to come off — `model.capabilities.clamp` is the whole of fitting the
    /// request to what will run it, and a size off the model's grid comes back on it rather
    /// than being refused. A length past one pass is planned as a chain before the clamp, as
    /// `generate(count:)` plans it, so no backend is asked for more frames than it runs.
    @discardableResult
    public func enqueue(
        _ settings: GenerationSettings, on model: ModelDescriptor, count: Int = 1,
        batchID: UUID = UUID(), requiresInstalledModel: Bool = false
    ) -> UUID? {
        if requiresInstalledModel, strictRefusal(for: model, settings: settings, count: count) != nil { return nil }
        let admission = remoteAdmission(for: model, settings: settings, count: count)
        guard case .admitted = admission else {
            // A submit that did nothing says so in `make logs`, the way a refused press of
            // Generate does, with the reason the device was given.
            logger.info("remote enqueue refused: \(admission.reason ?? "")")
            return nil
        }
        let segments = ChainPlan.segments(frames: settings.frames, capabilities: model.capabilities)
        var first = settings
        first.frames = segments[0]
        let request = model.capabilities.clamp(first)
        let batch = batchID
        let expanded = BatchExpansion.expand(request, count: count) { .random(in: .min ... .max) }
        for (index, settings) in expanded.enumerated() {
            queue.append(
                QueuedGeneration(
                    model: model,
                    settings: settings,
                    batchID: batch,
                    batchIndex: index,
                    chain: startChain(segments: segments, continuation: request.continuation),
                    requiresInstalledModel: requiresInstalledModel
                )
            )
        }
        if isDraining {
            logger.info("remote queued \(count) generation(s), \(self.queue.count) waiting")
        } else {
            drain()
        }
        return batch
    }
}
