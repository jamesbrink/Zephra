import Foundation
import ZephraCore

/// The sidebar's canvas list, worked out from the four things that know about a run: the
/// library index, this session's history, the queue, and whatever is being rendered.
///
/// Pure arithmetic over values, so the whole of it is tested in milliseconds without a window.
/// The view calls `build` and draws the answer; it never filters, groups, or sorts.
///
/// Two image sources on purpose. `LibraryIndex` lags `GenerationStore.history` by a debounced
/// folder scan, so a picture that has just landed would blink out of the run for a second if
/// only the index were read. A `.fresh` tile takes the wall's square the instant the image
/// exists and becomes an `.item` when the index catches up; matching is by file path, which is
/// the one thing both sides agree on. A seed still to come has no tile at all — the wall holds
/// finished pictures only.
public enum SessionTimeline {
    /// Today's runs, in the order the sidebar lists them: waiting runs in execution
    /// order, then the one being rendered, then the finished ones newest first.
    ///
    /// Only today's generated files are listed, because the sidebar is about the session rather
    /// than about the library. Everything in `history`, `queue`, and `running` is listed
    /// whatever its date: a run started before midnight is still this run.
    public static func build(
        items: [LibraryItem],
        history: [GeneratedImage],
        queue: [QueuedGeneration],
        running: QueuedGeneration?,
        isToday: (Date) -> Bool
    ) -> [TimelineRun] {
        let grouped = grouped(seeds(items: items, history: history, isToday: isToday))
        var queued: [UUID: [QueuedGeneration]] = [:]
        for entry in queue { queued[entry.batchID, default: []].append(entry) }
        return order(grouped.map(\.id), queue: queue, running: running).map { id in
            run(
                id: id,
                seeds: grouped.first { $0.id == id }?.seeds ?? [],
                queued: queued[id] ?? [],
                running: running?.batchID == id ? running : nil
            )
        }
    }

    /// Every run id there is to draw, in the order the sidebar wants them.
    ///
    /// Waiting runs follow the queue so drag order is execution order on both platforms.
    private static func order(
        _ finished: [UUID],
        queue: [QueuedGeneration],
        running: QueuedGeneration?
    ) -> [UUID] {
        var waiting: [UUID] = []
        for entry in queue where entry.batchID != running?.batchID && !waiting.contains(entry.batchID) {
            waiting.append(entry.batchID)
        }
        var ordered = waiting
        if let running { ordered.append(running.batchID) }
        return ordered + finished.filter { !ordered.contains($0) }
    }

    /// One run's row: its finished images, oldest first. A seed still to come has no tile; the
    /// running card above the wall is what says a run has more coming.
    private static func run(
        id: UUID,
        seeds: [Seed],
        queued: [QueuedGeneration],
        running: QueuedGeneration?
    ) -> TimelineRun {
        let tiles = seeds.sorted { $0.createdAt < $1.createdAt }.map(\.tile)
        let spoken = running ?? queued.first
        return TimelineRun(
            id: id,
            prompt: spoken?.settings.prompt ?? seeds.first?.prompt ?? "",
            size: spoken?.settings.size ?? seeds.first?.size ?? ImageSize(width: 0, height: 0),
            modelID: spoken?.model.id ?? seeds.first?.modelID ?? "",
            tiles: tiles,
            isRunning: running != nil,
            isWaiting: running == nil && !queued.isEmpty,
            queuedIDs: queued.map(\.id)
        )
    }
}
