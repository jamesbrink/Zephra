import Foundation
import ZephraCore

/// Running a generation, recording the result, and getting it onto disk. Split out of
/// `GenerationStore.swift` to keep the observed surface of the store readable on its own.
extension GenerationStore {
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
            transition(to: .ready)
        } catch BackendError.cancelled {
            transition(to: .ready)
        } catch let error as BackendError {
            transition(to: .failed(.backend(error)))
        } catch {
            transition(to: .failed(.backend(.generationFailed(error.localizedDescription))))
        }
    }

    /// Publishes a finished image straight away and only then starts writing it, so the canvas
    /// never waits on the file system.
    private func complete(_ data: Data, request: GenerationSettings, duration: Duration) {
        let image = GeneratedImage(
            pngData: data,
            settings: request,
            modelID: descriptor.id,
            duration: duration
        )
        current = image
        history.insert(image, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastDuration = duration
        transition(to: .ready)
        save(image)
    }

    private func save(_ image: GeneratedImage) {
        let library = library
        saveTask = Task.detached(priority: .utility) { [image] in
            do {
                let url = try library.write(image)
                await MainActor.run { self.attach(url, to: image.id) }
            } catch {
                let reason = error.localizedDescription
                await MainActor.run { self.saveFailed(reason) }
            }
        }
    }

    private func attach(_ url: URL, to id: GeneratedImage.ID) {
        if current?.id == id {
            current = current?.withFileURL(url)
        }
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = history[index].withFileURL(url)
        }
    }

    /// A failed write is worth showing, but the pixels are still in memory and still on the
    /// canvas, so `current` and `history` are left exactly as they were.
    private func saveFailed(_ reason: String) {
        guard state == .ready else { return }
        transition(to: .failed(.saveFailed(reason)))
    }

    func applyLoadEvent(_ event: EngineEvent) {
        switch event {
        case .download(let progress): state = .downloading(progress)
        case .progress(let progress): state = .loading(progress.phase)
        }
    }

    /// Progress that arrives after a cancel was asked for is dropped, so the interface does not
    /// flick back from `.cancelling` to `.generating` for the last step of a doomed run.
    private func applyGenerationEvent(_ event: EngineEvent) {
        guard case .generating = state, case .progress(let progress) = event else { return }
        state = .generating(progress)
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
