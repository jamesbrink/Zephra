import SwiftUI
import ZephraEngine

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
        let ranks = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($0.element, $0.offset) })
        var order = original.sorted {
            if let a = dates[$0], let b = dates[$1], a != b { return newest ? a > b : a < b }
            return newest ? ranks[$0]! > ranks[$1]! : ranks[$0]! < ranks[$1]!
        }
        if let pinned = store.pinnedQueueBatchID, order.contains(pinned) {
            order.removeAll { $0 == pinned }; order.insert(pinned, at: 0)
        }
        store.reorderQueue(batches: order, expectedEntries: store.queue.map(\.id))
    }
}
