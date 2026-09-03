import SwiftUI
import ZephraEngine

/// The library half of the window: the grid, and the facts about what is chosen in it.
///
/// The inspector is attached here rather than to the split view in `RootView`, so it is a
/// column of the detail pane and the sidebar's own splitter is left alone. That is the
/// arrangement the system draws correctly under a unified toolbar: the toolbar stays one
/// unbroken strip and the inspector's divider starts below it.
///
/// This is also where the size the grid is drawn at is decided, because it is the one thing
/// both halves need — the grid to lay cells out, the inspector to ask for a bigger picture.
struct LibraryDetail: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(ThumbnailCache.self) private var thumbnails

    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some View {
        @Bindable var workspace = workspace
        LibraryPane()
            .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, edge: edge))
            .inspector(isPresented: $workspace.inspectorVisible) {
                LibraryInspector()
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
    }
}

#Preview("Library") {
    LibraryDetail()
        .frame(width: 1000, height: 700)
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}
