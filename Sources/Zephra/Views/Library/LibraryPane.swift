import SwiftUI
import ZephraEngine

/// Everything made so far, as a grid, with the filter bar over it — or, while
/// `workspace.viewing` names one of them, that image full size instead. The zoom slider that
/// goes with the grid is a toolbar item declared from `WorkspaceToolbar`, not from here; see its
/// own doc comment for why.
///
/// It owns the selection, which is why it is a view and not a modifier: a selection belongs to
/// a window's library pane, survives a rescan under it, and is published to the menu bar so
/// Save as, Copy, Reveal and Delete mean the library while this is on screen — the viewer
/// included, since the publish sits here rather than inside `LibraryGrid`.
///
/// The filter bar shows only when it has something to say — a narrowed query or a live
/// selection — so an untouched library shows the grid alone; `RecentlyDeletedNotice` is outside
/// that condition because its own query check already gates it.
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
            // The index is published from here rather than from the grid, so Save as, Copy,
            // Reveal and Delete still know which files they are about while the viewer is up.
            .focusedSceneValue(\.libraryIndex, index)
            // `initial`, because a second window opens on whatever the shared workspace is
            // already viewing, and its own selection has to say so from the first frame.
            .onChange(of: workspace.viewing, initial: true) { _, id in
                guard let id else { return }
                selection.apply(LibraryCursor.Outcome(ids: [id], anchor: id))
            }
            // A query that no longer lists the picture closes the viewer: left open it would
            // show something the grid behind it cannot, with nowhere to step to.
            .onChange(of: index.sections) {
                guard workspace.viewing != nil, viewingItem == nil else { return }
                // The grid mounted in its place runs no change of its own for this, so what
                // it would have kept is kept here: nothing that the query no longer shows.
                selection.keeping(Set(index.sections.flatMap { $0.items.map(\.id) }))
                workspace.viewing = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if let item = viewingItem {
            LibraryViewer(item: item)
                // The viewer is the grid's stand-in for the keyboard, so the menu bar's file
                // commands act on what it shows rather than falling back to the canvas.
                .focusedValue(\.focusedLibraryGrid, selection)
        } else {
            LibraryGrid(selection: selection)
        }
    }

    /// The image `workspace.viewing` names, looked up in what the query is showing rather than
    /// in the whole index, or nil when there is none — either the grid is showing, or the item
    /// it named has gone (deleted, or filtered out from under it), in which case falling back
    /// to the grid is the only sensible thing left to do.
    private var viewingItem: LibraryItem? {
        guard let id = workspace.viewing else { return nil }
        return index.sections.lazy.flatMap(\.items).first { $0.id == id }
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
