import SwiftUI
import ZephraCore

/// The canvas's still picture, zoomable: `ImageCache`'s full-size pixels in a
/// `ZoomablePicture`, and until they are decoded the picture's own rectangle in the fill
/// `SessionImage` holds it with, so the frame is the right shape from the first frame.
///
/// It loads the way `SessionImage` does — the cache's pixels on the first frame when it has
/// them, else a decode off the main actor keyed to the picture it was asked for — rather than
/// through `SessionImage`, which the filmstrip and the inspector draw through and which lays
/// out a picture at its aspect rather than filling a pane.
struct CanvasStill: View {
    /// The picture to show.
    let image: GeneratedImage

    @Environment(ImageCache.self) private var cache
    @State private var loaded: (id: UUID, picture: DrawnPicture)?

    var body: some View {
        Group {
            if let picture {
                ZoomablePicture(picture: picture, key: image.id)
            } else {
                Rectangle().fill(.quaternary)
                    .aspectRatio(request.aspect, contentMode: .fit)
            }
        }
        .task(id: image.id) { await load() }
    }

    private var request: ImageCache.Request { .full(image) }

    /// What this picture loaded, else whatever the cache already holds for it.
    private var picture: DrawnPicture? {
        if let loaded, loaded.id == image.id { return loaded.picture }
        return cache.cached(image, .full)
    }

    private func load() async {
        guard let picture = await cache.load(image, .full) else { return }
        loaded = (image.id, picture)
    }
}
