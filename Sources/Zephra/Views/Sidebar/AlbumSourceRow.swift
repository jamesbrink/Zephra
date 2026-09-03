import SwiftUI
import ZephraEngine

/// One album in the sidebar: its name, how many images are in it, and the two things that can
/// be done to it.
///
/// The row does not own the edit its menu asks for. It writes into the one `AlbumEdit` the
/// sidebar holds — a row that owned its own would be a set of alerts as long as the album list,
/// all of them able to be up at once, and two rows could be renaming themselves at the same
/// time. Renaming happens right here, in place; only the deletion goes to an alert.
///
/// The count stays visible while the name is being typed, because the row is not becoming a
/// different thing: it is the same album with its name under the cursor.
struct AlbumSourceRow: View {
    /// The album this row stands for.
    let album: Album
    /// The sidebar's one edit, which this row reads to know whether it is the one being named.
    @Binding var edit: AlbumEdit?

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        HStack(spacing: 8) {
            if edit?.isRenaming(album) == true {
                Image(systemName: scope.systemImage)
                AlbumNameField(edit: $edit)
            } else {
                Label(album.name, systemImage: scope.systemImage)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            CountBadge(index.counts.perAlbum[album.id] ?? 0)
        }
        .frame(height: ZephraChrome.sidebarRowHeight)
        .tag(scope)
        .contextMenu {
            Button("Rename") { edit = AlbumEdit(kind: .rename, album: album) }
            Button("Delete Album…", role: .destructive) {
                edit = AlbumEdit(kind: .delete, album: album)
            }
        }
    }

    private var scope: LibraryScope { .album(album.id) }
}

#Preview("Album rows") {
    @Previewable @State var edit: AlbumEdit?
    let index = PreviewImages.library(count: 38)
    List {
        ForEach(index.albums) { album in
            AlbumSourceRow(album: album, edit: $edit)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 140)
    .environment(index)
}
