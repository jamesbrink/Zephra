import Foundation
import ZephraCore

/// Giving the weights back when nobody has asked for anything in a while.
///
/// Off unless the person turned it on. One clock, armed from one place — the end of
/// `transition(to:)`, which every state change funnels through — so a load, a generation, an
/// upscale, a swap and a failure all reset it by the fact of having happened, and nothing has to
/// remember to.
extension GenerationStore {
    /// Whether the weights are sitting doing nothing: loaded, ready, with no run, no queue, no
    /// upscale, no swap and no stop in flight.
    /// Never over a lost GPU, and the runtime is asked rather than `acceptsWork` alone: a clock
    /// already past its wait re-reads this, and a loss latched while it slept has not reached
    /// `deviceLost` yet, since nothing has transitioned. An unload is the last thing such a Mac
    /// should do — `releaseModel` refuses it too, which is the rule; this is the cheaper belt.
    var isIdleCandidate: Bool {
        acceptsWork && runtime?.isDeviceLost != true && state == .ready && queue.isEmpty
            && running == nil && !isUpscaling && !isSwappingModel && !isStoppingPreparation
            && loadedDescriptor != nil
    }

    /// Starts the idle clock, or stops it.
    func armIdleUnload() {
        idleTask?.cancel()
        idleTask = nil
        guard let delay = idleUnloadDelay.duration, isIdleCandidate else { return }
        idleTask = Task { [weak self, idleWait] in
            await idleWait(delay)
            // Read again on the main actor after the wait: the Mac may have been asked for
            // something in the meantime, and this is the one place that can tell. Weakly,
            // because the wait is up to an hour and a store nobody holds any more should go.
            guard !Task.isCancelled, let self, self.isIdleCandidate else { return }
            self.logger.info(
                "unloading \(self.loadedDescriptor?.id ?? "", privacy: .public) after \(self.idleUnloadDelay.rawValue) idle minutes"
            )
            self.unloadModel()
        }
    }
}
