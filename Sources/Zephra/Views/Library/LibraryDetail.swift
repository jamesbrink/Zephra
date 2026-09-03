import SwiftUI
import ZephraEngine

/// The library half of the window: the grid, at the size the slider asks for.
///
/// The inspector is not attached here: `WorkspaceDetail` puts one beside whichever pane is
/// showing, so the canvas and the library share it.
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
