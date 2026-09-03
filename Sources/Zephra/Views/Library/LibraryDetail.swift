import SwiftUI
import ZephraEngine

/// The library half of the window: the grid, at the size the slider asks for.
///
/// The inspector is not attached here. Attached to the detail column it became a column
/// *inside* the pane, and the unified toolbar was then split at its edge with the pane picker
/// stranded on the far side of the divider from the four items it belongs with. It lives on
/// the split view in `RootView` instead, where the trailing toolbar items stay together.
struct LibraryDetail: View {
    @Environment(ThumbnailCache.self) private var thumbnails

    @AppStorage(AppSettings.libraryThumbnailEdge)
    private var edge = AppSettings.initialLibraryThumbnailEdge

    var body: some View {
        LibraryPane()
            .environment(\.libraryThumbnails, LibraryThumbnails(cache: thumbnails, edge: edge))
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
