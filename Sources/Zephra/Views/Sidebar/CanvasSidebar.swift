import SwiftUI
import ZephraCore
import ZephraEngine

/// The sidebar while the canvas is up: the search, the session's runs, and the way to the
/// library pinned at the foot.
///
/// It works the runs out once per redraw and hands them down, because both the list and the
/// footer's count come from the same `SessionTimeline.build`, and that call walks the whole
/// index — a library of ten thousand pictures, filtered again on every denoising step, is not
/// something to do twice.
struct CanvasSidebar: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        let runs = runs
        VStack(spacing: 0) {
            SidebarSearch()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Divider()
            SessionTimelineList(runs: runs)
            Divider()
            TimelineFooterBar(count: runs.reduce(0) { $0 + $1.finishedCount })
        }
    }

    /// Today's runs. The day is worked out once and compared as a range, not asked of the
    /// calendar per image.
    private var runs: [TimelineRun] {
        let day = Calendar.current.startOfDay(for: Date())
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        return SessionTimeline.build(
            items: index.items,
            history: store.history,
            queue: store.queue,
            running: store.running,
            isToday: { $0 >= day && $0 < next }
        )
    }
}

#Preview("A run going, one waiting, two done") {
    let made = PreviewImages.run(of: 2)
    let flight = InterfacePreview.queuedRun(of: 2)
    CanvasSidebar()
        .frame(width: 280, height: 640)
        .environment(ImageCache())
        .environment(ThumbnailCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 8))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            images: made,
            running: flight[0],
            queue: Array(flight.dropFirst()) + InterfacePreview.queuedRun(of: 1)
        ))
}
