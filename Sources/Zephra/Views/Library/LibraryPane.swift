import SwiftUI
import ZephraEngine

/// Everything made so far, as a grid, with the filter bar over it and the zoom slider in the
/// toolbar.
///
/// It owns the selection, which is why it is a view and not a modifier: a selection belongs to
/// a window's library pane, survives a rescan under it, and is published to the menu bar so
/// Save as, Copy, Reveal and Delete mean the library while this is on screen.
///
/// The filter bar shows only when it has something to say — a narrowed query or a live
/// selection — so an untouched library shows the grid alone; `RecentlyDeletedNotice` is outside
/// that condition because its own query check already gates it. `LibraryZoomSlider` is declared
/// here rather than in `WorkspaceToolbar` so it vanishes with the pane on its own: an item
/// declared inside a column lands in that column's own toolbar section.
///
/// What opening an image means is not decided here: the inspector is a sibling of this pane
/// rather than a view inside it, so the action is handed down from `RootView`, above both.
struct LibraryPane: View {
    @State private var selection = LibrarySelection()

    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        LibraryGrid(selection: selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        if workspace.query.isNarrowed || !selection.ids.isEmpty {
                            LibraryFilterBar(selection: selection)
                        }
                    }
                    .animation(.snappy, value: workspace.query.isNarrowed)
                    .animation(.snappy, value: selection.ids.isEmpty)
                    RecentlyDeletedNotice(selection: selection)
                }
            }
            .overlay(alignment: .top) { LibraryFailureNotice() }
            .focusedSceneValue(\.librarySelection, selection)
            .toolbar {
                ToolbarItem(placement: .navigation) { LibraryZoomSlider() }
            }
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
