import SwiftUI
import ZephraCore
import ZephraEngine

/// The canvas sidebar: the queue and the images as they come out, in one list.
///
/// One list rather than a queue section above a grid of today's pictures, because they were
/// never two things. A run is queued, runs, and becomes four pictures; showing the waiting half
/// in one place and the finished half in another meant the same run appeared twice and moved
/// between them. Here a run is a row from the moment it is asked for, and what changes is what
/// its squares hold.
///
/// It is also what let the strip under the prompt capsule go. That strip pushed the capsule up
/// the moment a run started, so the picture jumped every time you pressed Generate.
struct SessionTimelineList: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        // The day is worked out once and compared as a range, not asked of the calendar per
        // image: a library of ten thousand pictures is filtered on every redraw, and a redraw
        // happens on every denoising step.
        let day = Calendar.current.startOfDay(for: Date())
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let runs = SessionTimeline.build(
            items: index.items,
            history: store.history,
            queue: store.queue,
            running: store.running,
            isToday: { $0 >= day && $0 < next }
        )
        let made = runs.reduce(0) { $0 + $1.finishedCount }
        List {
            Section {
                ForEach(runs) { run in
                    row(for: run)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if made > 0 {
                    Button("Show all \(made) in Library") {
                        // Coming to the library from the canvas means "show me everything": a
                        // view still narrowed by yesterday's search would look like an empty
                        // library.
                        workspace.query = LibraryQuery()
                        workspace.pane = .library
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if runs.isEmpty {
                    Text("Nothing made today yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                SectionHeader("Today", detail: "\(made)") {
                    if !store.queue.isEmpty {
                        Button("Clear queue") { store.clearQueue() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Which of the three shapes a run takes. The tiles are the same in all three; what differs
    /// is how much the row says about itself.
    @ViewBuilder
    private func row(for run: TimelineRun) -> some View {
        if run.isRunning {
            RunningRunCard(run: run)
        } else if run.isWaiting {
            WaitingRunCard(run: run)
        } else {
            FinishedRunRow(run: run)
        }
    }
}

#Preview("A run going, one waiting, one done") {
    let made = PreviewImages.run(of: 2)
    let flight = InterfacePreview.queuedRun(of: 2)
    let waiting = InterfacePreview.queuedRun(of: 1)
    SessionTimelineList()
        .frame(width: 280, height: 640)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            images: made,
            running: flight[0],
            queue: Array(flight.dropFirst()) + waiting
        ))
}

#Preview("Nothing yet") {
    SessionTimelineList()
        .frame(width: 280, height: 300)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(state: .ready))
}
