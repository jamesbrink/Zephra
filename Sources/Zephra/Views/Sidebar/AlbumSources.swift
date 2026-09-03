import SwiftUI
import ZephraEngine

/// The albums, on the library pane only, where filing images is what the sidebar is for.
///
/// One alert serves all three changes. `pending` is both what is being asked and whether
/// anything is being asked at all, so there is no way to reach a state where two of them are up
/// or where the name field is showing yesterday's word.
///
/// An alert rather than a confirmation dialog for the deletion, deliberately: a sheet-style
/// alert is a window, so it can be seen and driven, and a dialog that appears as a popover
/// under the pointer cannot.
struct AlbumSources: View {
    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace
    @State private var pending: AlbumEdit?

    var body: some View {
        Section {
            ForEach(index.albums) { album in
                AlbumSourceRow(album: album) { pending = $0 }
            }
        } header: {
            SectionHeader("Albums") {
                Button("New") { pending = AlbumEdit(kind: .create) }
                    .buttonStyle(.link)
            }
        }
        .alert(pending?.title ?? "", isPresented: isPrompting, presenting: pending) { edit in
            if edit.isNaming {
                TextField("Name", text: name)
                    .onSubmit { commit() }
            }
            Button(edit.confirmTitle, role: edit.kind == .delete ? .destructive : nil) { commit() }
                .disabled(!(pending?.isReady ?? false))
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { edit in
            if let message = edit.message { Text(message) }
        }
    }

    /// Goes through with whatever was being asked, and puts the sidebar on the new album so it
    /// is obvious something happened.
    private func commit() {
        guard let edit = pending, edit.isReady else { return }
        pending = nil
        switch edit.kind {
        case .create: workspace.show(scope: .album(index.createAlbum(named: edit.name).id))
        case .rename: edit.album.map { index.renameAlbum($0, to: edit.name) }
        case .delete: delete(edit.album)
        }
    }

    /// Removes an album, and steps the sidebar off it first: a scope naming an album that no
    /// longer exists would show an empty grid with no way back.
    private func delete(_ album: Album?) {
        guard let album else { return }
        if workspace.query.scope == .album(album.id) { workspace.query.scope = .all }
        index.deleteAlbum(album)
    }

    private var isPrompting: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var name: Binding<String> {
        Binding(get: { pending?.name ?? "" }, set: { pending?.name = $0 })
    }
}

#Preview("Albums") {
    List {
        AlbumSources()
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 200)
    .environment(LibraryIndex.preview(count: 38))
    .environment(WorkspaceSelection(pane: .library))
}
