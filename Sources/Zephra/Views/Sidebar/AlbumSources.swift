import SwiftUI
import ZephraEngine

/// The albums, on the library pane only, where filing images is what the sidebar is for.
///
/// Nothing is added from here. Making an album is `NewAlbumBar`'s job, pinned at the foot of the
/// sidebar where it does not move, and naming one happens in the row itself. What is left here
/// is the list and the one change that still deserves to be asked about.
///
/// An alert rather than a confirmation dialog for the deletion, deliberately: a sheet-style
/// alert is a window, so it can be seen and driven, and a dialog that appears as a popover
/// under the pointer cannot. It is raised only for a deletion — a rename lives in the same
/// `edit` value but is drawn by the row, so `isPrompting` asks the kind and not just whether
/// anything is being edited.
struct AlbumSources: View {
    /// The sidebar's one edit: a name being typed in a row, or a deletion waiting on the alert.
    @Binding var edit: AlbumEdit?

    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Section("Albums") {
            ForEach(index.albums) { album in
                AlbumSourceRow(album: album, edit: $edit)
            }
        }
        .alert(edit?.deleteTitle ?? "", isPresented: isPrompting, presenting: edit) { edit in
            Button("Delete", role: .destructive) { delete(edit.album) }
            Button("Cancel", role: .cancel) { self.edit = nil }
        } message: { edit in
            Text(edit.deleteMessage)
        }
    }

    /// Removes an album, and steps the sidebar off it first: a scope naming an album that no
    /// longer exists would show an empty grid with no way back.
    private func delete(_ album: Album) {
        edit = nil
        if workspace.query.scope == .album(album.id) { workspace.query.scope = .all }
        index.deleteAlbum(album)
    }

    /// Only a deletion raises the alert. The setter checks the kind too, so a rename that is
    /// still being typed is not cleared by the alert's own dismissal bookkeeping.
    private var isPrompting: Binding<Bool> {
        Binding(
            get: { edit?.kind == .delete },
            set: { if !$0, edit?.kind == .delete { edit = nil } }
        )
    }
}

#Preview("Albums") {
    @Previewable @State var edit: AlbumEdit?
    List {
        AlbumSources(edit: $edit)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 200)
    .environment(PreviewImages.library(count: 38))
    .environment(WorkspaceSelection(pane: .library))
}
