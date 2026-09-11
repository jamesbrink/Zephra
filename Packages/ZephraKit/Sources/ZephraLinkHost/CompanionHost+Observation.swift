import Foundation
import Observation
import ZephraLinkProtocol

/// Watching the store and the index, and turning what moved into deltas.
///
/// `withObservationTracking` fires once and is re-armed, which is what the loop below is: arm,
/// wait, sleep, publish, arm again. The sleep is what makes it correct as well as cheap — the
/// callback runs *before* the change lands, so reading the values in it would read the old ones,
/// and fifty milliseconds is both long enough for the write to have happened and short enough
/// that a phone never sees a step count it can feel lagging.
///
/// It runs only while somebody is listening. A Mac with no phone connected does no work here.
extension CompanionHost {
    /// How long the loop waits for a burst of changes to settle before it publishes.
    static let coalesce = Duration.milliseconds(50)
    /// The most preview frames a second any session is sent.
    static let previewsPerSecond = 10.0

    /// Starts watching, if nothing is already.
    func startObserving() {
        guard observation == nil else { return }
        published = CompanionPublication()
        observation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.awaitChange()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: CompanionHost.coalesce)
                guard !Task.isCancelled else { break }
                self?.publish()
            }
        }
    }

    /// Stops watching. Called when the last session goes and when the host is torn down.
    func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    /// Waits for any one of the tracked values to be about to change.
    private func awaitChange() async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                readTracked()
            } onChange: {
                continuation.resume()
            }
        }
    }

    /// Everything a phone is shown, touched once so the tracking registers all of it.
    ///
    /// `store.history` is read as ids and `index.items` as a count and its ids, so the loop arms
    /// on the arrays themselves rather than on any one picture's bytes.
    private func readTracked() {
        _ = store.state
        _ = store.current?.id
        _ = store.history.map(\.id)
        _ = store.queue
        _ = store.running
        _ = store.descriptor.id
        _ = store.availability
        _ = store.downloads.items
        _ = store.acceptsWork
        _ = store.livePreview
        _ = index.items
    }

    /// Publishes what has moved right now rather than waiting for the loop to come round.
    ///
    /// What the app calls when it knows something moved — a picture saved, a picture deleted —
    /// so a phone sees it in the same moment the Mac's own grid does.
    public func publishNow() { publish() }

    /// Publishes what has moved since the last pass, and the newest preview frame if one is due.
    private func publish() {
        guard !sessions.isEmpty else { return }
        publishEngine()
        publishQueue()
        publishHistory()
        publishModels()
        publishLibrary()
        publishPreview()
        published.hasPublished = true
    }

    /// Hands one delta to every session that has finished its handshake.
    func broadcast(_ delta: StateDelta) {
        for session in sessions { session.send(delta) }
    }
}
