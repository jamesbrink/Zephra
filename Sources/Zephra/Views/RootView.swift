import SwiftUI
import ZephraCore
import ZephraEngine

/// The window: a full-height sidebar, one of two panes beside it, and the engine's status as
/// the window's subtitle.
///
/// The title and the subtitle go on the split view rather than on the detail, so they stay put
/// when the pane changes and the unified toolbar draws them once, beside the sidebar's edge
/// rather than over it.
///
/// Loading the model is asked for one level up, in `WelcomeHost`, and not in either pane: a
/// pane is torn down when the other one shows, and a window left on the Library would
/// otherwise come back after a relaunch with nothing ever asking for the weights. It is above
/// this view rather than on it because on a first launch this view is not built at all and the
/// chooser still needs to know what is on disk.
/// The window's query is also copied into the library here, for the same reason: the sidebar
/// writes it whichever pane is showing, and the index has to be projecting the right thing by
/// the time the Library pane is built rather than a frame afterwards.
///
/// What opening an image means is decided here and not in the Library pane. The inspector is
/// a sibling of the pane inside `WorkspaceDetail`, not a view inside the pane, so an action
/// handed down from the pane never reaches the inspector's own "Open in Canvas" — it silently
/// took the environment's default and did nothing. Handed down from here, every place that
/// asks for it — the cell's menu, the sidebar's wall, and the inspector's own button — gets the
/// same one. The grid's double-click and Return ask for the other thing a picture can mean:
/// `\.viewLibraryItem`, the full-size viewer, provided beside it for the same reason.
struct RootView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        WorkspaceSplitView()
        // Above the panes rather than over them: the sidebar, the pane and the inspector all
        // lay out under the top inset, the same way they do under the toolbar strip. The
        // banner draws nothing at all when there is no update, so the inset is zero high.
        .safeAreaInset(edge: .top, spacing: 0) { UpdateBanner() }
        .disabled(store.isChangingImageDirectory)
        .navigationTitle("Zephra")
        .navigationSubtitle(store.windowSubtitle)
        .toolbar { WorkspaceToolbar() }
        // On Liquid Glass the toolbar floats over content by default, which let the inspector's
        // divider cut through it and left it with no consistent background. Forcing it visible
        // makes it an opaque full-width strip with a hairline under it, so the sidebar, the
        // pane, and the inspector all read as starting below it rather than under it.
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .environment(\.openLibraryItem, open)
        .environment(\.viewLibraryItem, view)
        .registeringLibraryUndo()
        .postingBackgroundNotices()
        .onChange(of: store.outputDirectory) {
            workspace.viewing = nil
            workspace.query = LibraryQuery(sort: workspace.query.sort)
        }
        .onChange(of: workspace.query, initial: true) { index.query = $1 }
    }

    /// Reads the image onto the canvas and goes there. The settings are deliberately not
    /// adopted — see `GenerationStore.open(_:)` — so looking at something never replaces the
    /// prompt being written.
    private func open(_ item: LibraryItem) {
        Task { await store.open(item) }
        workspace.pane = .canvas
    }

    /// Shows a library image full size without leaving the library. Unlike `open(_:)` this
    /// touches no engine state at all — the picture never goes near the canvas — it only names
    /// which item the library pane's viewer should show.
    private func view(_ item: LibraryItem) {
        workspace.pane = .library
        workspace.viewing = item.id
    }
}

#Preview("Ready") {
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}

#Preview("Generating, with a queue") {
    let run = InterfacePreview.queuedRun(of: 3)
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
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
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .downloading(
            DownloadProgressEvent(completedFiles: 3, totalFiles: 11, fraction: 0.34, bytesPerSecond: 46_000_000)
        )))
}

#Preview("Library") {
    RootView()
        .frame(width: 1180, height: 800)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}
