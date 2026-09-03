import SwiftUI
import ZephraEngine

/// One album in the sidebar: its name, how many images are in it, and the two things that can
/// be done to it.
///
/// The row does not own the alerts its menu asks for. It hands the request up to
/// `AlbumSources`, which holds one at a time — a row that owned its own would be a set of
/// alerts as long as the album list, all of them able to be up at once.
struct AlbumSourceRow: View {
    /// The album this row stands for.
    let album: Album
    /// Where a menu item's request goes.
    let onEdit: (AlbumEdit) -> Void

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        HStack(spacing: 8) {
            Label(album.name, systemImage: scope.systemImage)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            CountBadge(index.counts.perAlbum[album.id] ?? 0)
        }
        .frame(height: ZephraChrome.sidebarRowHeight)
        .tag(scope)
        .contextMenu {
            Button("Rename…") { onEdit(AlbumEdit(kind: .rename, album: album)) }
            Button("Delete Album…", role: .destructive) {
                onEdit(AlbumEdit(kind: .delete, album: album))
            }
        }
    }

    private var scope: LibraryScope { .album(album.id) }
}

#Preview("Album rows") {
    let index = PreviewImages.library(count: 38)
    return List {
        ForEach(index.albums) { album in
            AlbumSourceRow(album: album) { _ in }
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 140)
    .environment(index)
}
