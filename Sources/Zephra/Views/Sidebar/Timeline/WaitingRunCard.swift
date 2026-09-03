import SwiftUI
import ZephraCore
import ZephraEngine

/// A run still waiting its turn: what it will draw, how big, and a cross that takes the whole
/// run back out of the queue.
///
/// The cross removes every seed of the run rather than one of them. A run is what was asked
/// for, so it is what can be taken back; removing four seeds one at a time was never a thing
/// anybody wanted to do.
struct WaitingRunCard: View {
    /// The run that is waiting.
    let run: TimelineRun

    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(run.prompt)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(run.size.label)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    for id in run.queuedIDs { store.removeFromQueue(id) }
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
            RunTileGrid(tiles: run.tiles)
        }
    }
}

#Preview("Waiting") {
    let waiting = InterfacePreview.queuedRun(of: 2)
    List {
        ForEach(
            SessionTimeline.build(
                items: [], history: [], queue: waiting, running: nil,
                isToday: Calendar.current.isDateInToday)
        ) { run in
            WaitingRunCard(run: run)
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 260)
    .environment(ImageCache())
    .environment(ThumbnailCache())
    .environment(GenerationStore.preview(state: .ready, queue: waiting))
}
