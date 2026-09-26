import SwiftUI
import ZephraCore
import ZephraEngine

struct QueueRunActions: ViewModifier {
    let id: UUID
    @Environment(GenerationStore.self) private var store
    func body(content: Content) -> some View {
        content
            .draggable(id.uuidString)
            .dropDestination(for: String.self) { values, _ in
                guard let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                return apply(QueueOrder.moving(source, before: id, in: store.queuedBatchIDs))
            }
            .contextMenu {
                Button("Move Earlier", systemImage: "arrow.up") { move(true) }.disabled(!canMove(true))
                Button("Move Later", systemImage: "arrow.down") { move(false) }.disabled(!canMove(false))
            }
            .accessibilityAction(named: "Move Earlier") { move(true) }
            .accessibilityAction(named: "Move Later") { move(false) }
            .help("Drag to reorder queued runs, or use Move Earlier and Move Later")
    }
    private func canMove(_ earlier: Bool) -> Bool {
        let order = store.queuedBatchIDs
        guard let index = order.firstIndex(of: id), id != store.pinnedQueueBatchID else { return false }
        let other = index + (earlier ? -1 : 1)
        return order.indices.contains(other) && order[other] != store.pinnedQueueBatchID
    }
    private func move(_ earlier: Bool) {
        guard canMove(earlier) else { return }
        _ = apply(QueueOrder.adjacent(id, earlier: earlier, in: store.queuedBatchIDs))
    }
    private func apply(_ order: [UUID]) -> Bool {
        store.reorderQueue(batches: order, expectedEntries: store.queue.map(\.id))
    }
}
