import SwiftUI
import ZephraCore
import ZephraEngine

/// The window: a full-height sidebar, one of two panes beside it, and the engine's status as
/// the window's subtitle.
///
/// The title and the subtitle go on the split view rather than on the detail, so they stay put
/// when the pane changes and the unified toolbar draws them once, beside the sidebar's edge
/// rather than over it.
struct RootView: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            WorkspaceDetail()
        }
        .navigationTitle("Zephra")
        .navigationSubtitle(store.windowSubtitle)
        .toolbar { WorkspaceToolbar() }
    }
}

#Preview("Ready") {
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

#Preview("Generating, with a queue") {
    let run = InterfacePreview.queuedRun(of: 3)
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(
                phase: .denoising(step: 3, of: 4),
                fraction: 0.75,
                secondsPerStep: 8.2
            )),
            image: PreviewImages.sample(),
            running: run[0],
            queue: Array(run.dropFirst())
        ))
}

#Preview("Downloading") {
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .downloading(
            DownloadProgressEvent(completedFiles: 3, totalFiles: 11, fraction: 0.34, bytesPerSecond: 46_000_000)
        )))
}

#Preview("Library") {
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(GenerationStore.preview(state: .ready))
}
