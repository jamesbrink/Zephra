import SwiftUI
import ZephraEngine

/// Which albums the images are in, each removable, and the menu that puts them in another.
///
/// The names come from `index.name(of:)` rather than from the copy each image carries: the
/// manifest is where an album's current name lives, and the copy in the picture is a fallback
/// for a lost manifest that is allowed to be out of date. Reading the copy would mean a renamed
/// album kept its old name here until every member was rewritten.
struct AlbumChips: View {
    /// The images the chips act on.
    let ids: Set<LibraryItem.ID>
    /// The albums to show, already reduced to the ones every chosen image is in.
    let albums: [Album]

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        WrappingHStack {
            ForEach(albums) { album in
                Chip(index.name(of: album.id) ?? album.name) { index.remove(ids, from: album) }
            }
            AlbumMenu(ids: ids)
                .menuStyle(.button)
                .buttonStyle(.accessoryBar)
                .fixedSize()
        }
    }
}

#Preview("Albums") {
    let index = LibraryIndex.preview(count: 12)
    let item = index.items[0]
    return AlbumChips(ids: [item.id], albums: index.albums.filter { album in
        item.annotation.albums.contains { $0.id == album.id }
    })
    .padding(18)
    .frame(width: 300)
    .environment(index)
}
