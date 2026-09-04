import SwiftUI
import ZephraEngine

/// Everything made so far, as a grid, with the filter bar over it and the zoom slider in the
/// toolbar — or, while `workspace.viewing` names one of them, that image full size instead.
///
/// It owns the selection, which is why it is a view and not a modifier: a selection belongs to
/// a window's library pane, survives a rescan under it, and is published to the menu bar so
/// Save as, Copy, Reveal and Delete mean the library while this is on screen — the viewer
/// included, since the publish sits here rather than inside `LibraryGrid`.
///
/// The filter bar shows only when it has something to say — a narrowed query or a live
/// selection — so an untouched library shows the grid alone; `RecentlyDeletedNotice` is outside
/// that condition because its own query check already gates it. `LibraryZoomSlider` is declared
/// here rather than in `WorkspaceToolbar` so it vanishes with the pane on its own: an item
/// declared inside a column lands in that column's own toolbar section, and it has nothing to
/// say while the viewer is up besides.
///
/// What opening an image means is not decided here: the inspector is a sibling of this pane
/// rather than a view inside it, so the action is handed down from `RootView`, above both. The
/// viewer, unlike the grid, has no click of its own to select what it is showing, so this keeps
/// the selection in step with `workspace.viewing` itself — covering a double-click, Return, and
/// every arrow key or button the viewer steps with, in the one place that owns the selection.
struct LibraryPane: View {
    @State private var selection = LibrarySelection()

    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        content
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
                if viewingItem == nil {
                    ToolbarItem(placement: .navigation) { LibraryZoomSlider() }
                }
            }
            .onChange(of: workspace.viewing) { _, id in
                guard let id else { return }
                selection.apply(LibraryCursor.Outcome(ids: [id], anchor: id))
            }
    }

    @ViewBuilder
    private var content: some View {
        if let item = viewingItem {
            LibraryViewer(item: item)
        } else {
            LibraryGrid(selection: selection)
        }
    }

    /// The image `workspace.viewing` names, or nil when there is none — either the grid is
    /// showing, or the item it named has gone (deleted, or filtered out from under it), in
    /// which case falling back to the grid is the only sensible thing left to do.
    private var viewingItem: LibraryItem? {
        workspace.viewing.flatMap(index.item(for:))
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
