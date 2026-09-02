import SwiftUI
import ZephraEngine

/// The queued prompts in order, each removable, with one button to drop them all. It is shown
/// in `QueueChip`'s popover; nothing else presents it.
struct QueueList: View {
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

#Preview("Queue list") {
    QueueList()
        .environment(GenerationStore.preview(state: .ready))
}
