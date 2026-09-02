import SwiftUI
import ZephraEngine

/// How many prompts are waiting, with a popover to see them and take one back out. Absent
/// when nothing is queued, so the row stays quiet in the common case.
struct QueueChip: View {
    @Environment(GenerationStore.self) private var store
    @State private var isShowingQueue = false

    var body: some View {
        if !store.queue.isEmpty {
            Button {
                isShowingQueue = true
            } label: {
                Label("\(store.queue.count) queued", systemImage: "list.bullet")
                    .font(.callout)
                    .monospacedDigit()
            }
            .buttonStyle(.accessoryBar)
            .help("Prompts waiting to run")
            .popover(isPresented: $isShowingQueue, arrowEdge: .bottom) {
                QueueList()
            }
        }
    }
}

/// The queued prompts in order, each removable, with one button to drop them all.
private struct QueueList: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.queue) { item in
                HStack(spacing: 8) {
                    Text(item.settings.prompt)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(item.settings.size.label)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        store.removeFromQueue(item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove from queue")
                }
            }
            Divider()
            Button("Clear queue") { store.clearQueue() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .frame(width: 320)
    }
}

#Preview("Queue") {
    QueueChip()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
