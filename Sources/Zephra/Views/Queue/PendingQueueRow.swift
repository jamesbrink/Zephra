import SwiftUI
import ZephraCore
import ZephraEngine

/// One generation still waiting: what it will draw, how big, and a cross to take it back out.
struct PendingQueueRow: View {
    /// The generation waiting its turn.
    let item: QueuedGeneration

    @Environment(GenerationStore.self) private var store

    var body: some View {
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
            .foregroundStyle(.tertiary)
            .help("Remove from queue")
            .accessibilityLabel("Remove from queue")
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .chromePanel(.inset)
    }
}

#Preview("Waiting") {
    PendingQueueRow(item: QueuedGeneration(
        model: ModelCatalog.default,
        settings: GenerationSettings(
            prompt: "the same wall, no bicycle",
            size: ImageSize(width: 1024, height: 1024),
            steps: 4,
            guidance: 0,
            seed: 43
        )
    ))
    .padding()
    .frame(width: 280)
    .environment(GenerationStore.preview(state: .ready))
}
