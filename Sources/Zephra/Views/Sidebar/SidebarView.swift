import SwiftUI
import ZephraCore
import ZephraEngine

/// The full-height column down the left of the window, and the one thing in the app that is not
/// the same in both panes.
///
/// On the canvas it is the session: the search field, then the queue and the images as they come
/// out, in one list. That is what the canvas needs a column for — the picture is on screen, and
/// what you want beside it is what else this afternoon produced and what is still coming.
///
/// In the library the pane is already showing the pictures at a size worth looking at, so the
/// sidebar stops repeating them and does the filing instead: the standing collections, the
/// models, the tags, the albums, and the way back out of Recently Deleted.
///
/// The search field is on both, because the search you type on the canvas is the search the
/// library answers. Only the chips are dropped from the canvas: they narrow a grid that is not
/// on screen.
struct SidebarView: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            switch workspace.pane {
            case .canvas:
                SidebarSearch()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                Divider()
                SessionTimelineList()
            case .library:
                SidebarHeader()
                Divider()
                SidebarSources()
                Divider()
                RecentlyDeletedRow()
            }
        }
    }
}

#Preview("The canvas, idle") {
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("The canvas, with a run going") {
    let run = InterfacePreview.queuedRun(of: 3)
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            images: PreviewImages.run(of: 2),
            running: run[0],
            queue: Array(run.dropFirst())
        ))
}

#Preview("The library") {
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}
