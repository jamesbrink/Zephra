import SwiftUI
import ZephraCore
import ZephraEngine

/// The canvas sidebar's list: the queue and the images as they come out.
///
/// Top to bottom it reads future, present, past: the runs still waiting as cards, the run being
/// rendered in amber with its step segments, and under those the wall of today's pictures. The
/// wall starts with the running run's own squares, so a seed lands where its dashed place was
/// and nothing below it moves — and when the run is over its squares are simply the newest on
/// the wall, which is where they already were.
///
/// It is also what let the strip under the prompt capsule go. That strip pushed the capsule up
/// the moment a run started, so the picture jumped every time you pressed Generate.
struct SessionTimelineList: View {
    /// Today's runs, in the order the sidebar lists them. Built once by `CanvasSidebar`.
    let runs: [TimelineRun]

    @Environment(GenerationStore.self) private var store

    var body: some View {
        let wall = SessionTimeline.wall(of: runs)
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
                if !wall.isEmpty {
                    TimelineTileGrid(tiles: wall)
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
                SectionHeader("Today", detail: "\(runs.reduce(0) { $0 + $1.finishedCount })") {
                    if !store.queue.isEmpty {
                        Button("Clear Queue") { store.clearQueue() }
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
    let runs = SessionTimeline.build(
        items: [], history: made, queue: Array(flight.dropFirst()) + waiting, running: flight[0],
        isToday: { _ in true })
    SessionTimelineList(runs: runs)
        .frame(width: 280, height: 640)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            images: made,
            running: flight[0],
            queue: Array(flight.dropFirst()) + waiting
        ))
}

#Preview("Nothing yet") {
    SessionTimelineList(runs: [])
        .frame(width: 280, height: 300)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}
