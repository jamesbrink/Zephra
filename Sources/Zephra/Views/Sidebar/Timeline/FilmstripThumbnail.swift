import SwiftUI
import ZephraCore
import ZephraEngine

/// One image this session made, before the library index has caught up with the file.
///
/// It fills whatever cell it is put in, the way `LibraryThumbnail` does, because the two take
/// turns in the same square of a run: this one the instant the image exists, the indexed one a
/// folder scan later. A tile that changed size as it settled would make the grid twitch.
///
/// No number on it: the order it was made in carries no meaning, and the picture is the only
/// label worth having. The ring and the corner are the grid's, not this view's.
struct FilmstripThumbnail: View {
    /// The image this thumbnail stands for.
    let image: GeneratedImage

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button {
            store.select(image)
        } label: {
            SessionImage(request: .thumbnail(image))
        }
        .buttonStyle(.plain)
        .draggable(image)
        .help(image.settings.prompt)
        .contextMenu { FreshImageMenu(image: image) }
        .accessibilityLabel(image.settings.prompt)
    }
}

#Preview("Thumbnail") {
    FilmstripThumbnail(image: PreviewImages.sample())
        .frame(width: 96, height: 96)
        .padding()
        .environment(ImageCache())
        .environment(PreviewImages.library(count: 4))
        .environment(GenerationStore.preview(state: .ready))
}
