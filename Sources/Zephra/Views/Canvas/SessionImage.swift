import AppKit
import SwiftUI
import ZephraStyle

/// A picture this session made, drawn from `ImageCache`, decoded off the main actor.
///
/// The one view over that cache: the canvas, the fresh-image inspector and the filmstrip all
/// draw through it, so none of them holds a bitmap or asks for a decode in `body`. The frame
/// is held at the request's aspect before the pixels arrive, so the canvas's picture lands in
/// the rectangle its placeholder was filling and a filmstrip tile never changes shape.
///
/// The pixels kept are keyed to the request they were made for, so a view handed a new image
/// draws that image's cached pixels or its placeholder — never the old picture cropped into
/// the new shape for a frame while the decode runs.
struct SessionImage: View {
    /// The image, the kind, and the shape to hold for it.
    let request: ImageCache.Request

    @Environment(ImageCache.self) private var cache
    @State private var loaded: Loaded?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(request.aspect, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .modifier(SessionImageFade(fades: request.kind == .full, trigger: loaded?.key))
            .task(id: request.key) { await load() }
    }

    /// What is on screen: what this request loaded, else whatever the cache already holds for
    /// it, so a picture seen before is on its first frame.
    private var picture: NSImage? {
        if let loaded, loaded.key == request.key { return loaded.image }
        return cache.cached(request.image, request.kind)
    }

    private func load() async {
        if let hit = cache.cached(request.image, request.kind) {
            loaded = Loaded(key: request.key, image: hit)
            return
        }
        loaded = nil
        guard let image = await cache.load(request.image, request.kind) else { return }
        loaded = Loaded(key: request.key, image: image)
    }

    /// Pixels and the request they answer.
    private struct Loaded {
        let key: ImageCache.Request.Key
        let image: NSImage
    }
}

#Preview("Finished image") {
    SessionImage(request: .full(PreviewImages.sample()))
        .padding(40)
        .frame(width: 520, height: 520)
        .background(Color.canvasBackground)
        .environment(ImageCache())
}

#Preview("Thumbnail") {
    SessionImage(request: .thumbnail(PreviewImages.sample()))
        .frame(width: 96, height: 96)
        .padding()
        .environment(ImageCache())
}
