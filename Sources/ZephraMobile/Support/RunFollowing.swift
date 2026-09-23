import Foundation
import ZephraLinkProtocol

/// The run one press of Generate queued, followed through the Mac's own snapshot so the line
/// under the button says where it has got to rather than where it started.
///
/// An acceptance is a moment, not a state: "Queued on Halcyon" was true when the Mac answered
/// and false a second later, and a note written once at that answer stood under the button
/// through the whole render and after the picture had landed in Today. So the note is read
/// again off every snapshot the Mac sends. The run is the Mac's `batchID`, which its queue,
/// the entry being rendered and Today's runs all carry.
///
/// Absence is ambiguous, which is why `seen` exists. The Mac answers a press before its
/// coalesced deltas say the run is queued, so a batch named nowhere yet is a run on its way
/// in; a batch named nowhere *after* it was seen has finished, been stopped or been refused.
/// A failure ends the following too, but only one the phone watched happen: a Mac already
/// sitting on an earlier failure takes a new press from `.failed`, and its engine may still
/// say so in the first snapshot after the answer.
struct RunFollowing: Equatable, Sendable {
    /// The run, as the Mac's queue and Today name it.
    let batchID: UUID
    /// The Mac it went to, for the sentence.
    let hostName: String
    /// Whether any snapshot has named the run yet.
    private(set) var seen = false
    /// Whether an engine that was not failed has been read since the press.
    private(set) var sawEngineWorking = false
    /// What to say under Generate, or nil once the run is over.
    private(set) var note: String?

    /// Starts following a run the Mac has just accepted.
    init(batchID: UUID, hostName: String) {
        self.batchID = batchID
        self.hostName = hostName
        note = "Queued on \(hostName)"
    }

    /// Whether there is nothing left to say about the run.
    var hasEnded: Bool { note == nil }

    /// Reads one snapshot of the Mac the run went to. Once ended, nothing moves it again.
    mutating func read(_ snapshot: StateSnapshot) {
        guard !hasEnded else { return }
        let engine = snapshot.engine
        if engine.kind != .failed { sawEngineWorking = true }
        let run = snapshot.today.first { $0.id == batchID }
        if snapshot.running?.batchID == batchID || run?.state == .running {
            seen = true
            note = "\(engine.phase ?? "Generating") on \(hostName)"
        } else if snapshot.queue.contains(where: { $0.batchID == batchID })
            || run?.state == .waiting {
            seen = true
            note = "Queued on \(hostName)"
        } else if run?.state == .finished || seen
            || (engine.kind == .failed && sawEngineWorking) {
            note = nil
        }
    }
}
