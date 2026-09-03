import SwiftUI
import ZephraEngine

/// Everything made so far, as a grid, with the filter bar over it.
///
/// It owns the selection, which is why it is a view and not a modifier: a selection belongs to
/// a window's library pane, survives a rescan under it, and is published to the menu bar so
/// Save as, Copy, Reveal and Delete mean the library while this is on screen.
///
/// What opening an image means is not decided here: the inspector is a sibling of this pane
/// rather than a view inside it, so the action is handed down from `RootView`, above both.
struct LibraryPane: View {
    @State private var selection = LibrarySelection()

    var body: some View {
        LibraryGrid(selection: selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    LibraryFilterBar(selection: selection)
                    RecentlyDeletedNotice(selection: selection)
                }
            }
            .overlay(alignment: .top) { LibraryFailureNotice() }
            .focusedSceneValue(\.librarySelection, selection)
    }
}

#Preview("Library pane") {
    LibraryPane()
        .frame(width: 900, height: 700)
        .environment(\.libraryThumbnails, LibraryThumbnails(cache: ThumbnailCache(), edge: 168))
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(GenerationStore.preview(state: .ready))
}
