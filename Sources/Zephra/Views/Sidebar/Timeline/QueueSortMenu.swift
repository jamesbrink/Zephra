import SwiftUI
import ZephraEngine
import ZephraCore

struct QueueSortMenu: View {
    @Environment(GenerationStore.self) private var store
    var body: some View {
        Menu("Sort Queue", systemImage: "arrow.up.arrow.down") {
            Button("Oldest Request First") { sort(newest: false) }
            Button("Newest Request First") { sort(newest: true) }
        }.disabled(store.queuedBatchIDs.count < 2)
    }
    private func sort(newest: Bool) {
        let dates = Dictionary(uniqueKeysWithValues: store.promptHistory.entries.map { ($0.id, $0.createdAt) })
        let original = store.queuedBatchIDs
        var order = QueueOrder.chronological(original, dates: dates, newest: newest)
        if let pinned = store.pinnedQueueBatchID, order.contains(pinned) {
            order.removeAll { $0 == pinned }; order.insert(pinned, at: 0)
        }
        store.reorderQueue(batches: order, expectedEntries: store.queue.map(\.id))
    }
}
