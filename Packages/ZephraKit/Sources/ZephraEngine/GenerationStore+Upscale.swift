import Foundation
import ZephraCore

/// Making a finished picture larger: a post-process, not a generation.
///
/// It needs no model loaded, so it is offered from `.idle` and from `.failed` as well as from
/// `.ready`, and on every way out — finished, failed, or stopped — the engine is put back into
/// the state it was in when the upscale began. Nothing may be queued while one runs, so there is
/// never a queue waiting on a model that was never loaded.
extension GenerationStore {
    /// Whether this store can make a picture larger right now: there is an upscaler in the
    /// build, the engine is not busy with a model, and no upscale is already under way.
    ///
    /// A preview store has no upscaler, so its buttons are greyed with no extra rule.
    public var canUpscale: Bool {
        guard !isChangingModelDirectory, !isChangingImageDirectory, !isShuttingDown, !isSwappingModel,
              !isStoppingPreparation, !deletionInProgress, upscalerFactory != nil, upscaleTask == nil else { return false }
        switch state {
        case .idle, .ready, .failed: return true
        default: return false
        }
    }

    /// Whether a picture is being made larger, including one that is being stopped. The task
    /// rather than the state, so the seconds spent in `.cancelling` still count as an upscale
    /// and nothing starts a generation into them.
    public var isUpscaling: Bool { upscaleTask != nil }

    /// Makes the picture behind `source` `factor` times larger on each edge and writes the
    /// result into the library as a picture of its own.
    ///
    /// Does nothing unless `canUpscale`, which is what makes a second press while one is running
    /// a no-op rather than a second job, and nothing for a picture that has not been saved: the
    /// parent's own record is read from the file.
    public func upscale(_ source: UpscaleSource, factor: Int) {
        guard canUpscale, let url = source.fileURL, let inference = inferenceActor() else { return }
        let resumeState = state
        transition(to: .upscaling(UpscaleProgressEvent(completedTiles: 0, totalTiles: 1)))
        upscaleTask = Task {
            await self.runUpscale(url, factor: factor, from: resumeState, on: inference)
        }
    }

    /// Drives one upscale from the read of the parent to the state it puts back.
    ///
    /// The activity assertion keeps the Mac awake for the same reason a generation's does: it is
    /// a stretch of silent Metal work with no user input behind it.
    private func runUpscale(
        _ url: URL, factor: Int, from resumeState: EngineState, on inference: InferenceActor
    ) async {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Upscaling image"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let clock = ContinuousClock()
        let started = clock.now
        let pump = EngineEventPump { [weak self] event in self?.applyUpscaleEvent(event) }
        do {
            guard let parent = await UpscaleParent.read(url) else {
                throw UpscaleError.failed("That picture could not be read.")
            }
            let request = UpscaleRequest(factor: factor)
            let data = try await pump.run { sink in
                try await inference.upscale(parent.pngData, request, events: sink)
            }
            try Task.checkCancellation()
            completeUpscale(data, parent: parent, factor: factor, duration: clock.now - started)
        } catch is CancellationError {
        } catch UpscaleError.cancelled {
        } catch {
            upscaleFailed(url, reason: error.readableMessage)
        }
        resumeAfterUpscale(from: resumeState)
    }

    /// Puts back the state the upscale interrupted, and only then lets another one start.
    ///
    /// `drain()` on an empty queue is exactly the "bring the loaded model in line with the
    /// chosen one" step, which is what completes a model switch asked for while this ran.
    private func resumeAfterUpscale(from resumeState: EngineState) {
        upscaleTask = nil
        transition(to: resumeState)
        if resumeState == .ready { drain() }
    }

    /// The parent is untouched and still on disk, so this is a notice rather than a state: the
    /// failure screen's remedy reloads the model, which would be no remedy at all here.
    private func upscaleFailed(_ url: URL, reason: String) {
        logger.error("upscale failed: \(reason, privacy: .public)")
        lastLibraryFailure = LibraryFailure(
            itemID: url.standardizedFileURL.path(percentEncoded: false),
            action: .upscale,
            reason: reason)
    }

    /// Progress that arrives after a stop was asked for is dropped, so the canvas does not flick
    /// back from `.cancelling` to a tile count for the last tile of a doomed run.
    private func applyUpscaleEvent(_ event: EngineEvent) {
        guard case .upscaling = state, case .upscale(let progress) = event else { return }
        state = .upscaling(progress)
    }
}
