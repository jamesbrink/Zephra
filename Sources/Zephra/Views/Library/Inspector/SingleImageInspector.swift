import SwiftUI
import ZephraCore
import ZephraEngine

/// One image, at length: the picture, what it was asked for, how it was made, and what has
/// been said about it.
///
/// The prompt is the one thing in this column that is prose rather than data, and it is set
/// as secondary text in the system face so the column reads as one thing; the serif is kept for
/// the canvas's invitation. Everything below the prompt is a table, and looks like one.
struct SingleImageInspector: View {
    /// The image being looked at.
    let item: LibraryItem

    @Environment(ThumbnailCache.self) private var thumbnails
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picture
                if !item.prompt.isEmpty {
                    Text(item.prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ImageFactsView(facts: facts, edited: item.provenance.record?.referenceBytes != nil)
                TagChips(ids: [item.id], tags: item.tags)
                AlbumChips(ids: [item.id], albums: albums)
                Spacer(minLength: 8)
                InspectorActions(item: item)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The picture with its star over it, which is where a favourite is both shown and set.
    private var picture: some View {
        LibraryThumbnail(item: item)
            .clipShape(
                RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
            )
            .environment(
                \.libraryThumbnails, LibraryThumbnails(cache: thumbnails, size: .extraLarge)
            )
            .overlay(alignment: .topTrailing) {
                FavouriteToggle(ids: [item.id])
                    .font(.title3)
                    .padding(10)
                    .shadow(color: .black.opacity(ZephraChrome.shadowOpacity), radius: 4, y: 1)
            }
    }

    /// The catalog's name for the model when this build still ships it, and the identifier
    /// written into the file when it does not — which is the honest answer, not a blank.
    private var facts: ImageFacts {
        ImageFacts(item, modelName: item.modelID.flatMap(ModelCatalog.descriptor(id:))?.fullName)
    }

    /// The albums it is in, in the sidebar's order, named by the manifest rather than by the
    /// copy the picture carries.
    private var albums: [Album] {
        index.albums.filter { album in
            item.annotation.albums.contains { $0.id == album.id }
        }
    }
}

#Preview("One image") {
    let index = PreviewImages.library(count: 12)
    return SingleImageInspector(item: index.items[0])
        .frame(width: 320, height: 700)
        .environment(ThumbnailCache())
        .environment(index)
        .environment(GenerationStore.preview(state: .ready))
        .environment(WorkspaceSelection(pane: .library))
}
