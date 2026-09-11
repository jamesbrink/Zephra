import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

/// Today's runs, as the canvas sidebar draws them and the phone repeats them.
///
/// `SessionTimeline` does the whole of the grouping — this only turns its tiles into the file
/// names and dates `RunSummary` takes, which is the one thing the protocol package cannot do
/// for itself: reading a `LibraryItem`'s name and a fresh `GeneratedImage`'s URL is the Mac's
/// job. A tile with no file yet is dropped rather than sent nameless: the phone asks for a
/// thumbnail by name, and a row of blanks it can never fill is worse than a shorter row.
public enum RunSummaryProjection {
    /// The runs a store and an index make between them, in the sidebar's own order.
    public static func runs(
        items: [LibraryItem],
        history: [GeneratedImage],
        queue: [QueuedGeneration],
        running: QueuedGeneration?,
        calendar: Calendar = .current
    ) -> [RunSummary] {
        SessionTimeline.build(
            items: items, history: history, queue: queue, running: running,
            isToday: { calendar.isDateInToday($0) }
        ).map { run in RunSummary(run, tiles: tiles(of: run)) }
    }

    /// One run's finished pictures, as a name and a date each.
    private static func tiles(of run: TimelineRun) -> [(fileName: String, createdAt: Date)] {
        run.tiles.compactMap { tile in
            switch tile {
            case .item(let item): (fileName: item.fileName, createdAt: item.createdAt)
            case .fresh(let image):
                image.fileURL.map { (fileName: $0.lastPathComponent, createdAt: image.createdAt) }
            }
        }
    }
}
