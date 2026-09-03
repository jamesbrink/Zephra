import SwiftUI
import ZephraEngine

/// Everything made so far, as a grid, with the filter bar over it.
///
/// It owns the selection, which is why it is a view and not a modifier: a selection belongs to
/// a window's library pane, survives a rescan under it, and is published to the menu bar so
/// Save as, Copy, Reveal and Delete mean the library while this is on screen.
///
/// It also decides what opening an image means, and hands that down as one closure. Three
/// places ask for it and none of them should have to hold both the store and the window's
/// selection to say so.
struct LibraryPane: View {
    @State private var selection = LibrarySelection()

    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        LibraryGrid(selection: selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    LibraryFilterBar(selection: selection)
                    RecentlyDeletedNotice(selection: selection)
                }
            }
            .overlay(alignment: .top) { LibraryFailureNotice() }
            .environment(\.openLibraryItem, open)
            .focusedSceneValue(\.librarySelection, selection)
    }

    /// Reads the image onto the canvas and goes there. The settings are deliberately not
    /// adopted — see `GenerationStore.open(_:)` — so looking at something never replaces the
    /// prompt being written.
    private func open(_ item: LibraryItem) {
        Task { await store.open(item) }
        workspace.pane = .canvas
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
