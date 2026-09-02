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

#Preview("Queue") {
    QueueChip()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
