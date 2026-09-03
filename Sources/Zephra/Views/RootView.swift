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
/// Loading the model is asked for here, not in either pane, because a pane is torn down when
/// the other one shows. A window left on the Library would otherwise come back after a
/// relaunch with nothing ever asking for the weights.
/// The window's query is also copied into the library here, for the same reason: the sidebar
/// writes it whichever pane is showing, and the index has to be projecting the right thing by
/// the time the Library pane is built rather than a frame afterwards.
///
/// The inspector hangs off the split view rather than off the Library pane. Inside the pane it
/// was a column within a column, and the unified toolbar split at its edge: the pane picker
/// ended up on the content side of the divider and the other four items on the inspector side,
/// one group torn in half. Here the trailing items stay together above the inspector.
///
/// Which is also why what opening an image means is decided here and not in the Library pane.
/// The inspector is a sibling of the pane, not a view inside it, so an action handed down from
/// the pane never reaches the inspector's own "Open in canvas" — it silently took the
/// environment's default and did nothing. Handed down from here, every place that asks (the
/// grid's double-click, the cell's menu, Return, and the inspector) gets the same one.
struct RootView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            WorkspaceDetail()
        }
        .inspector(isPresented: inspectorVisible) {
            LibraryInspector()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .navigationTitle("Zephra")
        .navigationSubtitle(store.windowSubtitle)
        .toolbar { WorkspaceToolbar() }
        .environment(\.openLibraryItem, open)
        .onChange(of: workspace.query, initial: true) { index.query = $1 }
        .task { await store.bootstrapFromInterface() }
    }

    /// Reads the image onto the canvas and goes there. The settings are deliberately not
    /// adopted — see `GenerationStore.open(_:)` — so looking at something never replaces the
    /// prompt being written.
    private func open(_ item: LibraryItem) {
        Task { await store.open(item) }
        workspace.pane = .canvas
    }

    /// Shown only beside the Library, since there is nothing for it to say about the canvas.
    /// Written as a binding rather than an `if` so hiding it animates the column away instead
    /// of taking the whole modifier out from under the view.
    private var inspectorVisible: Binding<Bool> {
        Binding(
            get: { workspace.pane == .library && workspace.inspectorVisible },
            set: { workspace.inspectorVisible = $0 }
        )
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
