import SwiftUI
import ZephraCore
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

#Preview("One seed running") {
    let run = InterfacePreview.queuedRun(of: 1)
    VStack(spacing: 0) { QueueSection() }
        .frame(width: 280)
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            running: run[0]
        ))
}

#Preview("A run of four") {
    let run = InterfacePreview.queuedRun(of: 4)
    VStack(spacing: 0) { QueueSection() }
        .frame(width: 280)
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            running: run[0],
            queue: Array(run.dropFirst())
        ))
}
