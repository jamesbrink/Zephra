import Foundation
import ZephraCore

/// Running a generation, recording the result, and getting it onto disk. Split out of
/// `GenerationStore.swift` to keep the observed surface of the store readable on its own.
extension GenerationStore {
    /// Kicks off `request` on the inference actor. Only `generate()` and the queue call this.
    func start(_ request: GenerationSettings) {
        guard let inference else { return }
        clearLivePreview()
        transition(to: .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)))
        generationTask = Task { await self.run(request, on: inference) }
    }

    /// Returns to `.ready`, then works on down the queue. Every way a run can end goes through
    /// here so the queue never stalls.
    private func finish() {
        running = nil
        clearLivePreview()
        transition(to: .ready)
        drain()
    }

    /// Drives one generation from start to finish. The activity assertion keeps the Mac awake:
    /// a generation is a long stretch of silent Metal work with no user input behind it.
    func run(_ request: GenerationSettings, on inference: InferenceActor) async {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Generating image"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let clock = ContinuousClock()
        let started = clock.now
        let pump = EngineEventPump { [weak self] event in self?.applyGenerationEvent(event) }
        do {
            let data = try await pump.run { sink in
                try await inference.generate(request, events: sink)
            }
            complete(data, request: request, duration: clock.now - started)
        } catch is CancellationError {
            finish()
        } catch BackendError.cancelled {
            finish()
        } catch let error as BackendError {
            fail(with: .backend(error))
        } catch {
            fail(with: .backend(.generationFailed(error.localizedDescription)))
        }
    }

    /// Everything a failed generation puts down: the queue, the run, and the frame it was last
    /// showing. One place rather than two, because the two `catch` clauses differ only in how
    /// they name the error.
    private func fail(with error: EngineError) {
        queue.removeAll()
        running = nil
        clearLivePreview()
        transition(to: .failed(error))
    }

    /// Publishes a finished image straight away and only then starts writing it, so the canvas
    /// never waits on the file system.
    ///
    /// It reaches the canvas only while the canvas is following the run. A result that lands
    /// while the user is looking at something else still enters history, the wall, and the
    /// library; what it does not do is yank the picture out from under them.
    private func complete(_ data: Data, request: GenerationSettings, duration: Duration) {
        let image = GeneratedImage(
            pngData: data,
            settings: request,
            modelID: loadedDescriptor?.id ?? descriptor.id,
            duration: duration,
            batchID: running?.batchID
        )
        if followsRun { current = image }
        history.insert(image, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastDuration = duration
        save(image)
        finish()
    }

    private func save(_ image: GeneratedImage) {
        let library = library
        saveTask = Task.detached(priority: .utility) { [image] in
            do {
                let url = try library.write(image)
                await MainActor.run { self.attach(url, to: image.id) }
            } catch {
                let failure = SaveFailure(imageID: image.id, reason: error.localizedDescription)
                await MainActor.run { self.saveFailed(failure) }
            }
        }
    }

    func attach(_ url: URL, to id: GeneratedImage.ID) {
        lastSaveFailure = nil
        if current?.id == id {
            current = current?.withFileURL(url)
        }
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = history[index].withFileURL(url)
        }
        onImageSaved?(url)
    }

    /// A failed write is worth showing, but the pixels are still in memory and still on the
    /// canvas, so `current` and `history` are left exactly as they were.
    ///
    /// It does not become an engine state either. A save lands after `finish()` has already
    /// started the next queued generation, so failing the engine here would stop a queue over
    /// a full disk, and the remedy on the failure screen reloads the model, which would be no
    /// remedy at all. The interface shows this as a notice until an image saves cleanly.
    func saveFailed(_ failure: SaveFailure) {
        logger.error("save failed: \(failure.reason, privacy: .public)")
        lastSaveFailure = failure
    }

    func applyLoadEvent(_ event: EngineEvent) {
        switch event {
        case .download(let progress): state = .downloading(progress)
        case .build(let progress): state = .building(progress)
        case .progress(let progress): state = .loading(progress.phase)
        // A load never upscales anything; the case is here because the switch is exhaustive.
        case .upscale: break
        }
    }

    /// Progress that arrives after a cancel was asked for is dropped, so the interface does not
    /// flick back from `.cancelling` to `.generating` for the last step of a doomed run.
    private func applyGenerationEvent(_ event: EngineEvent) {
        guard case .generating = state, case .progress(let progress) = event else { return }
        state = .generating(progress)
        // Kept out of the state, which is compared and hashed on every transition, and which a
        // late event would otherwise be able to put a stale frame back into.
        if let preview = progress.preview { livePreview = preview }
    }

    /// The one place `state` changes for a reason worth a log line. Progress updates go through
    /// the two apply methods above instead, because one line per denoising step is noise.
    func transition(to newState: EngineState) {
        guard newState != state else { return }
        logger.info(
            "state \(self.state.logName, privacy: .public) -> \(newState.logName, privacy: .public)"
        )
        state = newState
    }
}
