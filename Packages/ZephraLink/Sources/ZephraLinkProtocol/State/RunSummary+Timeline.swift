import Foundation
import ZephraEngine

/// One of the Mac's timeline runs, summarised.
///
/// The dates come from the tiles rather than from the run, because `TimelineRun` has none: a
/// run is a group, and when it started is when its oldest picture landed. A run still in
/// flight has no finish, and one with no picture yet has neither.
extension RunSummary {
    /// The wire form of one timeline run, given the file name and date of each of its tiles.
    ///
    /// The tiles are passed in rather than read off the run, because reading a `LibraryItem`'s
    /// name and a fresh `GeneratedImage`'s URL is the Mac's job and it needs no protocol.
    public init(_ run: TimelineRun, tiles: [(fileName: String, createdAt: Date)]) {
        let dates = tiles.map(\.createdAt).sorted()
        self.init(
            id: run.id,
            prompt: run.prompt,
            modelID: run.modelID,
            width: run.size.width,
            height: run.size.height,
            state: run.isRunning ? .running : (run.isWaiting ? .waiting : .finished),
            fileNames: tiles.map(\.fileName),
            seedCount: run.seedCount,
            startedAt: dates.first,
            finishedAt: run.isRunning || run.isWaiting ? nil : dates.last)
    }
}
