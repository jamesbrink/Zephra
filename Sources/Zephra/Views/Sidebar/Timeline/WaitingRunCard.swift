import SwiftUI
import ZephraCore
import ZephraEngine

/// A run still waiting its turn: what it will draw, how many and how big, and a cross that
/// takes the whole run back out of the queue.
///
/// No squares under it. Nothing in a waiting run has started, so a row of dashed places would
/// only say "four" at eighty points a piece; the count says it in a word, and the places appear
/// on the wall when the run does.
///
/// The cross removes every seed of the run rather than one of them. A run is what was asked
/// for, so it is what can be taken back; removing four seeds one at a time was never a thing
/// anybody wanted to do.
struct WaitingRunCard: View {
    /// The run that is waiting.
    let run: TimelineRun

    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Text(run.prompt)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(detail)
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
    }

    /// The size, and the count before it when there is more than one seed to make.
    private var detail: String {
        let seeds = run.tiles.count
        return seeds > 1
            ? "\(seeds) seeds \(ImageFacts.separator) \(run.size.label)"
            : run.size.label
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
