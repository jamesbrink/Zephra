import SwiftUI
import ZephraCore
import ZephraEngine

/// One earlier image, small. No number on it: the order it was made in carries no meaning,
/// and the picture is the only label worth having.
struct FilmstripThumbnail: View {
    /// The image this thumbnail stands for.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store
    @Environment(ImageCache.self) private var cache

    var body: some View {
        Button {
            store.select(image)
        } label: {
            thumbnail
        }
        .buttonStyle(.plain)
        .draggable(image)
        .help(image.settings.prompt)
        .contextMenu {
            CanvasFavouriteButton(image: image)
            Divider()
            Button("Save as…") { ImageExport.saveAs(image) }
            Button("Copy") { ImageExport.copyToPasteboard(image) }
            Button("Reveal in Finder") { ImageExport.revealInFinder(image) }
            if store.descriptor.capabilities.supportsReferenceImage {
                Button("Use as Reference") { store.useAsReference(image.pngData) }
            }
            Divider()
            // Nothing is asked first: the file goes to the Trash, so this is undoable in the
            // Finder, and a dialog on every discarded image would be in the way.
            Button("Delete", role: .destructive) { store.delete(image.id) }
        }
        .accessibilityLabel(image.settings.prompt)
    }

    private var thumbnail: some View {
        Group {
            if let bitmap = cache.thumbnail(for: image) {
                Image(nsImage: bitmap).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black.opacity(0.3)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous))
        .overlay {
            let isSelected = store.current?.id == image.id
            RoundedRectangle(cornerRadius: ZephraChrome.thumbnailRadius, style: .continuous)
                // The unselected border is the system separator, not a white wash: white on a
                // light background is invisible, which is what it used to be in light mode.
                .strokeBorder(
                    isSelected ? Color.primary.opacity(0.9) : ZephraChrome.hairline,
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }
}

#Preview("Thumbnail") {
    FilmstripThumbnail(image: PreviewImages.sample())
        .padding()
        .environment(ImageCache())
        .environment(LibraryIndex.preview(count: 4))
        .environment(GenerationStore.preview(state: .ready))
}
