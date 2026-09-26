import Foundation

extension GenerationStore {
    /// Queue groups in execution order. A batch's seeds and chain passes stay together.
    public var queuedBatchIDs: [UUID] {
        var seen = Set<UUID>()
        return queue.compactMap { seen.insert($0.batchID).inserted ? $0.batchID : nil }
    }
    public var pinnedQueueBatchID: UUID? {
        running?.batchID ?? (isSwitchingForQueue ? queue.first?.batchID : nil)
    }
    /// Absolute intent, checked atomically against the entries the caller saw.
    /// Returns false after enqueue/removal/drain, so stale gestures never move different work.
    @discardableResult
    public func reorderQueue(batches: [UUID], expectedEntries: [UUID]) -> Bool {
        guard acceptsWork, expectedEntries == queue.map(\.id),
              batches.count == queuedBatchIDs.count, Set(batches) == Set(queuedBatchIDs) else { return false }
        if let pinned = pinnedQueueBatchID, queue.contains(where: { $0.batchID == pinned }),
           batches.first != pinned { return false }
        let groups = Dictionary(grouping: queue, by: \.batchID)
        queue = batches.flatMap { groups[$0] ?? [] }
        return true
    }
}
