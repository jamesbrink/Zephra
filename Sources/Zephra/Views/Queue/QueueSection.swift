import SwiftUI
import ZephraEngine

/// What the engine is working on, in the sidebar: the seed being rendered, then the ones
/// waiting behind it.
///
/// Absent entirely when there is nothing to show, its own divider included, so an idle sidebar
/// has no empty band in the middle of it.
struct QueueSection: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if store.running != nil || !store.queue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Queue") {
                    Button("Clear") { store.clearQueue() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .fontWeight(.semibold)
                if let running = store.running {
                    RunningQueueCard(item: running)
                }
                ForEach(store.queue) { item in
                    PendingQueueRow(item: item)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
        }
    }
}
