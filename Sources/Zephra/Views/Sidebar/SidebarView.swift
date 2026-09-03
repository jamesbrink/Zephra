import SwiftUI
import ZephraCore
import ZephraEngine

/// The full-height column down the left of the window: what you are looking for at the top,
/// what is being made in the middle, where to look at the bottom.
///
/// It is the same in both panes on purpose. The search you type on the canvas is the search
/// the library answers, and a queue that moved when the pane changed would be a second queue.
struct SidebarView: View {
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            Divider()
            // The queue draws its own divider under itself, so an idle sidebar has one line
            // here rather than two touching ones.
            QueueSection()
            SidebarSources()
            Divider()
            RecentlyDeletedRow()
        }
    }
}

#Preview("Idle") {
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("With a run going") {
    let run = InterfacePreview.queuedRun(of: 3)
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            running: run[0],
            queue: Array(run.dropFirst())
        ))
}
