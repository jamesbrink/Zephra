import SwiftUI
import ZephraEngine
import ZephraStyle

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
    @State private var picture: DrawnPicture?

    var body: some View {
        ground
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(nsImage: picture.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            // Keyed on the file's state too, so a rewritten file bakes again; the old picture
            // stays up while it does, which is the rule the doc comment above already states.
            .task(id: ThumbnailRequest(item, thumbnails?.size)) { await load() }
    }

    /// The checkerboard under a picture that carries transparency, and otherwise the fill
    /// every cell has always had. The decoded thumbnail is what answers, until it is here:
    /// the file's own header does, so a cell is never checkered and then not.
    @ViewBuilder
    private var ground: some View {
        if picture?.hasAlpha ?? item.hasAlpha {
            TransparencyGround()
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    /// Asks the cache, drawing whatever it already holds on the first frame so a picture that
    /// has been seen before does not flash.
    private func load() async {
        guard let thumbnails else { return }
        if let hit = thumbnails.cache.cached(item, size: thumbnails.size) {
            picture = hit
            return
        }
        guard let loaded = await thumbnails.cache.load(item, size: thumbnails.size) else { return }
        picture = loaded
    }
}

#Preview("Placeholder") {
    LibraryThumbnail(item: PreviewImages.library(count: 1).items[0])
        .frame(width: 168, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
        .padding(24)
}
