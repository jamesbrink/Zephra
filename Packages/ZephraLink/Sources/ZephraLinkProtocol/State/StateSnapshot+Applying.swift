import Foundation

/// One delta folded into the state it edits.
///
/// Here rather than on the phone, because the Mac's `StateDelta` and the snapshot it edits are
/// one design: a case added there without an answer here would leave a phone drawing a state
/// that quietly stopped moving, and a `switch` with no `default` is what makes that a build
/// failure instead.
extension StateSnapshot {
    /// This state with one change applied.
    public func applying(_ delta: StateDelta) -> StateSnapshot {
        var next = self
        switch delta {
        case .engine(let engine): next.engine = engine
        case .queue(let queue): next.queue = queue
        case .running(let running): next.running = running
        case .historyInserted(let entry):
            next.history.removeAll { $0.id == entry.id }
            next.history.insert(entry, at: 0)
        case .historyRemoved(let id): next.history.removeAll { $0.id == id }
        case .model(let model): next.model = model
        case .availability(let availability): next.availability = availability
        case .downloads(let downloads): next.downloads = downloads
        case .today(let today): next.today = today
        case .library(let change): next.libraryCount = Self.count(next.libraryCount, after: change)
        case .acceptsWork(let accepts): next.acceptsWork = accepts
        }
        return next
    }

    /// How many pictures the library holds after one change.
    ///
    /// An upsert leaves the count alone: an entry that has changed and an entry that has
    /// arrived are the same message, and guessing which would drift from the folder. A reset
    /// carries the real total, which is what puts the count right again.
    private static func count(_ current: Int, after change: LibraryChange) -> Int {
        switch change {
        case .reset(_, let total): total
        case .upserted: current
        case .removed(let names): max(0, current - names.count)
        }
    }
}
