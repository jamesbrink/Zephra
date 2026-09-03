import SwiftUI
import ZephraEngine

/// Several images at once: what they are, what they have in common, and what can be done to all
/// of them.
///
/// Everything here is about the set rather than about any member of it. Tags and albums show
/// only what every image agrees on, and a fact that differs reads "Multiple" — showing the
/// first image's would be a claim about images that do not share it.
struct MultipleSelectionInspector: View {
    /// The images chosen, in the order the grid is showing them.
    let items: [LibraryItem]

    @Environment(ThumbnailCache.self) private var thumbnails
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StackedThumbnails(items: items)
                    .environment(
                        \.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .large)
                    )
                HStack(spacing: 8) {
                    Text("\(items.count) images selected")
                        .font(.headline)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    FavouriteToggle(ids: ids)
                        .font(.title3)
                }
                SharedFactsView(items: items)
                TagChips(ids: ids, tags: sharedTags)
                AlbumChips(ids: ids, albums: sharedAlbums)
                Spacer(minLength: 8)
                MultipleSelectionActions(items: items)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ids: Set<LibraryItem.ID> { Set(items.map(\.id)) }

    /// The tags every one of them carries. A chip with a cross on it means "these images have
    /// this"; a tag only half of them had would make one press do two different things.
    private var sharedTags: [String] {
        guard let first = items.first else { return [] }
        return first.tags.filter { tag in items.allSatisfy { $0.tags.contains(tag) } }
    }

    /// The albums every one of them is in, on the same reasoning.
    private var sharedAlbums: [Album] {
        index.albums.filter { album in
            !items.isEmpty && items.allSatisfy { item in
                item.annotation.albums.contains { $0.id == album.id }
            }
        }
    }
}

#Preview("Several images") {
    let index = LibraryIndex.preview(count: 12)
    return MultipleSelectionInspector(items: Array(index.items.prefix(4)))
        .frame(width: 320, height: 700)
        .environment(ThumbnailCache())
        .environment(index)
        .environment(GenerationStore.preview(state: .ready))
}
