import SwiftUI
import ZephraCore
import ZephraEngine

/// The full-height column down the left of the window, and the one thing in the app that is not
/// the same in both panes.
///
/// On the canvas it is the session, `CanvasSidebar`: the search field, then the queue and the
/// images as they come out, with the way to the library at the foot. That is what the canvas
/// needs a column for — the picture is on screen, and what you want beside it is what else this
/// afternoon produced and what is still coming.
///
/// In the library the pane is already showing the pictures at a size worth looking at, so the
/// sidebar stops repeating them and does the filing instead: the standing collections, the
/// models, the tags, the albums, and the way back out of Recently Deleted.
///
/// The search field is on both, because the search you type on the canvas is the search the
/// library answers. Only the chips are dropped from the canvas: they narrow a grid that is not
/// on screen.
///
/// It also owns the album edit, which is a name being typed into one row or a deletion waiting
/// on an alert. It is held here, above both the list and the New Album bar under it, because a
/// new album is made in one place and named in another: the bar makes it and hands the naming to
/// the row, and only a value that outlives both can carry that across.
struct SidebarView: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index
    @State private var albumEdit: AlbumEdit?

    var body: some View {
        VStack(spacing: 0) {
            switch workspace.pane {
            case .canvas:
                CanvasSidebar()
            case .library:
                SidebarHeader()
                Divider()
                SidebarSources(albumEdit: $albumEdit)
                Divider()
                RecentlyDeletedRow()
                Divider()
                NewAlbumBar(action: newAlbum)
            }
        }
        .focusedSceneValue(\.newAlbum, published)
    }

    /// ⌘N is the same action as the bar, so the menu bar is handed the action itself rather than
    /// being told how to make an album. It has to be an action: the naming lives in this view's
    /// own `@State`, which nothing outside the window's view tree can reach, and putting album
    /// bookkeeping into `ZephraEngine` or `WorkspaceSelection` to get at it would be moving
    /// interface state somewhere it does not belong. On the canvas nothing is published, which
    /// is what greys the menu item out.
    private var published: (@MainActor () -> Void)? {
        workspace.pane == .library ? newAlbum : nil
    }

    /// Makes an album, shows it, and puts the cursor in its name.
    ///
    /// The album exists before it is named, which is what lets one code path do the naming: what
    /// the bar starts is a rename of a real album, the same edit the row's own Rename starts.
    /// Escape then leaves "Untitled Album" behind rather than unmaking anything, which is what
    /// the Finder does with a new folder.
    private func newAlbum() {
        let album = index.createAlbum(named: "Untitled Album")
        workspace.show(scope: .album(album.id))
        albumEdit = AlbumEdit(kind: .rename, album: album)
    }
}

#Preview("The canvas, idle") {
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("The canvas, with a run going") {
    let run = InterfacePreview.queuedRun(of: 3)
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.75)),
            images: PreviewImages.run(of: 2),
            running: run[0],
            queue: Array(run.dropFirst())
        ))
}

#Preview("The library") {
    SidebarView()
        .frame(width: 280, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .library))
        .environment(PreviewImages.library(count: 38))
        .environment(ThumbnailCache())
        .environment(GenerationStore.preview(state: .ready))
}
