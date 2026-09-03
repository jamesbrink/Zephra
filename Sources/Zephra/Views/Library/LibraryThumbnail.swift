import SwiftUI
import ZephraEngine

/// One image's pixels, at whatever size the surrounding pane asked for.
///
/// The square is filled before the picture arrives, and the picture that is already there is
/// kept while a bigger one is baked. Both are the same rule: the grid's geometry must never
/// depend on whether a decode has finished, or dragging the size slider would make the whole
/// wall of images jump as each one blinks out and back.
struct LibraryThumbnail: View {
    /// The image to show.
    let item: LibraryItem

    @Environment(\.libraryThumbnails) private var thumbnails
    @State private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: ThumbnailRequest(item.id, thumbnails?.size)) { await load() }
    }

    /// Asks the cache, drawing whatever it already holds on the first frame so a picture that
    /// has been seen before does not flash.
    private func load() async {
        guard let thumbnails else { return }
        if let hit = thumbnails.cache.cached(item, size: thumbnails.size) {
            image = hit
            return
        }
        guard let loaded = await thumbnails.cache.load(item, size: thumbnails.size) else { return }
        image = loaded
    }
}

#Preview("Placeholder") {
    LibraryThumbnail(item: LibraryIndex.preview(count: 1).items[0])
        .frame(width: 168, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
        .padding(24)
}
