import Foundation

extension SessionTimeline {
    /// The wall, cut into blocks: the running run and any run of more than one square stand on
    /// their own; consecutive finished runs of one square flow together.
    ///
    /// Waiting runs are not on the wall at all — their cards say what is coming — so they are
    /// skipped here rather than by the caller. Runs are taken in the order `build` lists them,
    /// which is what puts the running run's dashed places at the head of the wall.
    public static func blocks(of runs: [TimelineRun]) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var singles: [TimelineRun] = []
        func flushSingles() {
            guard let first = singles.first else { return }
            blocks.append(TimelineBlock(id: first.id, tiles: singles.flatMap(\.tiles)))
            singles.removeAll()
        }
        for run in runs where !run.isWaiting {
            if run.isRunning || run.tiles.count > 1 {
                flushSingles()
                blocks.append(TimelineBlock(id: run.id, tiles: run.tiles))
            } else {
                singles.append(run)
            }
        }
        flushSingles()
        return blocks
    }
}
