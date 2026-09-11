import Foundation
import ZephraLinkProtocol

/// The two frozen states the library and Today surfaces are photographed in.
///
/// A file of its own beside `MobilePreview+Fixtures`, for that file's own reason turned round:
/// the fixture holds what a Mac would send at rest, and a surface that is *about* movement — a
/// run in flight, a queue behind it — cannot be frozen in a file without going stale the moment
/// the numbers move. So it is built from the fixture here, the way `midRun` is.
extension MobilePreview {
    /// The snapshot one state shows, which is the fixture's for every state that is at rest.
    static func shaped(_ snapshot: StateSnapshot, for state: MobilePreviewState) -> StateSnapshot {
        switch state {
        case .generating: midRun(snapshot) ?? snapshot
        case .today: todayRuns(snapshot) ?? snapshot
        default: snapshot
        }
    }

    /// Whether the library should open on its first picture, which is the `viewer` state.
    static var opensViewer: Bool { state == .viewer }

    /// The same snapshot with one run going and one waiting behind it, on top of the two the
    /// fixture has already finished.
    ///
    /// The run in flight is `midRun`'s, so the engine and the row agree about the step it is
    /// on; both runs carry batch identities of their own, since the fixture's finished runs
    /// already own theirs and a list cannot hold the same run twice.
    static func todayRuns(_ snapshot: StateSnapshot?) -> StateSnapshot? {
        guard var snapshot = midRun(snapshot), var running = snapshot.running else { return nil }
        running.batchID = Self.runningBatch
        let waiting = QueuedEntry(
            id: UUID(uuidString: "5B2A9C41-7E63-4D18-9A0F-C3E7D5B41208")!,
            batchID: Self.waitingBatch,
            batchIndex: 0,
            modelID: snapshot.model.id,
            prompt: "a lighthouse in fog, long exposure",
            width: 1024,
            height: 1024,
            seed: 3_310_552_004_991_233,
            frames: 1)
        snapshot.running = running
        snapshot.queue = [waiting]
        snapshot.today = [summary(of: running, .running), summary(of: waiting, .waiting)]
            + snapshot.today
        return snapshot
    }

    /// One queued entry as the row Today draws it. Nothing has landed from either, so both
    /// carry no file names: the strip of thumbnails is what a finished run has.
    private static func summary(of entry: QueuedEntry, _ state: RunSummary.State) -> RunSummary {
        RunSummary(
            id: entry.batchID, prompt: entry.prompt, modelID: entry.modelID, width: entry.width,
            height: entry.height, state: state, fileNames: [], seedCount: state == .running ? 2 : 1,
            startedAt: state == .running ? Date().addingTimeInterval(-30) : nil, finishedAt: nil)
    }

    private static let runningBatch = UUID(uuidString: "0C6E48D3-92A1-4F57-B3D8-7E2A1F905C46")!
    private static let waitingBatch = UUID(uuidString: "9F31A7C2-5D84-4B06-8E1A-7C40D92B6355")!
}
