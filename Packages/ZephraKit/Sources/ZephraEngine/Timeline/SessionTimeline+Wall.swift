import Foundation

extension SessionTimeline {
    /// The wall: every square of every run that is on it, in one flow, newest run first and
    /// oldest square first within a run.
    ///
    /// One flow rather than a block per run. A batch in a grid of its own ended its row early,
    /// and a wall of batches and singles read as ragged rather than as grouped; a run still
    /// reads as a run because its squares are adjacent, and the inspector says which run a
    /// square belongs to. Waiting runs are not on the wall at all — their cards say what is
    /// coming — so they are skipped here rather than by the caller. Runs are taken in the order
    /// `build` lists them, which is what puts the running run's own finished squares at the
    /// head, adjacent, with no place held for what has not landed yet — that is the running
    /// card's job, above the wall.
    public static func wall(of runs: [TimelineRun]) -> [TimelineTile] {
        runs.filter { !$0.isWaiting }.flatMap(\.tiles)
    }
}
