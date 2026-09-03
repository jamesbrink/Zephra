import SwiftUI
import ZephraCore
import ZephraEngine

/// The canvas sidebar: the queue and the images as they come out, in one list.
///
/// Top to bottom it reads future, present, past: the runs still waiting as cards, the run being
/// rendered in amber with its step segments, and under those one wall of today's pictures. The
/// wall starts with the running run's own squares, so a seed lands where its dashed place was
/// and nothing below it moves — and when the run is over its squares are simply the newest on
/// the wall, which is where they already were.
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
        let tiles = runs.filter { !$0.isWaiting }.flatMap(\.tiles)
        List {
            Section {
                ForEach(runs.filter(\.isWaiting)) { run in
                    WaitingRunCard(run: run)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let running = runs.first(where: \.isRunning) {
                    RunningRunCard(run: running)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !tiles.isEmpty {
                    TimelineTileGrid(tiles: tiles)
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
